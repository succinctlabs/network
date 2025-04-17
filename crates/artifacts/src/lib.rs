#![deny(clippy::pedantic)]
#![allow(clippy::module_name_repetitions)]
#![allow(clippy::similar_names)]
#![allow(clippy::items_after_statements)]
#![allow(clippy::missing_errors_doc)]

use std::time::Duration;

use anyhow::{Context, Result, anyhow};
use aws_config::{BehaviorVersion, Region, retry::RetryConfig};
use aws_sdk_s3::{
    Client as S3Client,
    config::{IdentityCache, StalledStreamProtectionConfig},
    primitives::{ByteStream, SdkBody},
};
use aws_smithy_async::rt::sleep::default_async_sleep;
use bytes::Bytes;
use lazy_static::lazy_static;
use serde::{Serialize, de::DeserializeOwned};
use spn_artifact_types::ArtifactType;
use tokio::sync::OnceCell;
use tracing::instrument;

lazy_static! {
    /// A globally accessible S3 client.
    static ref S3_CLIENT: OnceCell<S3Client> = OnceCell::new();
}

#[derive(serde::Serialize, serde::Deserialize, Clone, PartialEq, ::prost::Message)]
pub struct Artifact {
    /// The unique identifier for the artifact, representing its location in the S3
    /// bucket.
    #[prost(string, tag = "1")]
    pub id: ::prost::alloc::string::String,
    /// The label for the artifact (e.g., program, stdin, proof).
    #[prost(string, tag = "2")]
    pub label: ::prost::alloc::string::String,
    /// The expiration time for the artifact, as a Unix timestamp.
    #[prost(int32, optional, tag = "5")]
    pub expiry: ::core::option::Option<i32>,
}

impl Artifact {
    #[instrument(fields(label = self.label, id = self.id), skip_all)]
    pub async fn upload<T: Serialize>(
        &self,
        item: T,
        s3_bucket: &str,
        s3_region: &str,
        artifact_type: ArtifactType,
    ) -> Result<()> {
        let s3_client = get_s3_client(s3_region).await;
        let data = bincode::serialize(&item).context("Failed to serialize data")?;
        upload_file(s3_client, s3_bucket, &self.id, artifact_type, Bytes::from(data)).await
    }

    #[instrument(fields(label = self.label, id = self.id), skip_all)]
    pub async fn download_raw(
        &self,
        s3_bucket: &str,
        s3_region: &str,
        artifact_type: ArtifactType,
    ) -> Result<Bytes> {
        let s3_client = get_s3_client(s3_region).await;
        download_file(s3_client, s3_bucket, &self.id, artifact_type).await
    }

    pub async fn download_program<T: DeserializeOwned + Send + Sync + 'static>(
        &self,
        s3_bucket: &str,
        s3_region: &str,
    ) -> Result<T> {
        let bytes = self.download_raw(s3_bucket, s3_region, ArtifactType::Program).await?;
        bincode::deserialize(&bytes).context("Failed to deserialize program")
    }

    pub async fn download_stdin<T: DeserializeOwned + Send + Sync + 'static>(
        &self,
        s3_bucket: &str,
        s3_region: &str,
    ) -> Result<T> {
        let bytes = self.download_raw(s3_bucket, s3_region, ArtifactType::Stdin).await?;
        bincode::deserialize(&bytes).context("Failed to deserialize stdin")
    }

    pub async fn download_proof<T: DeserializeOwned + Send + Sync + 'static>(
        &self,
        s3_bucket: &str,
        s3_region: &str,
    ) -> Result<T> {
        let bytes = self.download_raw(s3_bucket, s3_region, ArtifactType::Proof).await?;
        bincode::deserialize(&bytes).context("Failed to deserialize proof")
    }

    #[instrument(fields(label = self.label, id = self.id), skip_all)]
    pub async fn upload_raw(
        &self,
        data: Bytes,
        s3_bucket: &str,
        s3_region: &str,
        artifact_type: ArtifactType,
    ) -> Result<()> {
        let s3_client = get_s3_client(s3_region).await;
        upload_file(s3_client, s3_bucket, &self.id, artifact_type, data).await
    }
}

/// Extracts the artifact ID from an S3 URL.
///
/// Given an S3 URL in the format `s3://<bucket>/path/to/artifact_id`, this function parses and
/// returns just the artifact ID component (the last path segment).
pub fn parse_artifact_id_from_s3_url(s3_url: &str) -> Result<String> {
    s3_url.split('/').last().map(String::from).ok_or_else(|| anyhow!("Invalid S3 URL format"))
}

/// Returns the S3 prefix for a given artifact type.
///
/// Maps each artifact type to a specific S3 prefix, allowing different artifact types to have
/// different lifecycle policies in S3. Each prefix can have its own expiration rules configured in
/// the S3 bucket.
#[must_use]
pub fn get_s3_prefix(artifact_type: ArtifactType) -> &'static str {
    match artifact_type {
        ArtifactType::UnspecifiedArtifactType => "artifacts",
        ArtifactType::Program => "programs",
        ArtifactType::Stdin => "stdins",
        ArtifactType::Proof => "proofs",
    }
}

/// Constructs the complete S3 key for an artifact.
///
/// Combines the appropriate S3 prefix for the artifact type with the artifact ID to create the
/// full S3 key used to store or retrieve the artifact from the bucket.
#[must_use]
pub fn get_s3_key(artifact_type: ArtifactType, id: &str) -> String {
    format!("{}/{}", get_s3_prefix(artifact_type), id)
}

async fn get_s3_client(s3_region: &str) -> &'static S3Client {
    S3_CLIENT
        .get_or_init(|| async {
            // Load the default config.
            let mut base = aws_config::load_defaults(BehaviorVersion::latest()).await.to_builder();

            // Set the retry config.
            base.set_retry_config(Some(
                RetryConfig::standard()
                    .with_max_attempts(7)
                    .with_max_backoff(Duration::from_secs(30)),
            ))
            .set_sleep_impl(default_async_sleep())
            .set_region(Some(Region::new(s3_region.to_string())));

            // Disable stalled stream protection.
            base.set_stalled_stream_protection(Some(StalledStreamProtectionConfig::disabled()));

            // Refresh identity slightly more frequently than the default to avoid ExpiredToken
            // errors.
            base.set_identity_cache(Some(
                IdentityCache::lazy()
                    .load_timeout(Duration::from_secs(10))
                    .buffer_time(Duration::from_secs(300))
                    .build(),
            ));

            // Build the client.
            let config = base.build();
            S3Client::new(&config)
        })
        .await
}

async fn download_file(
    client: &S3Client,
    bucket: &str,
    id: &str,
    artifact_type: ArtifactType,
) -> Result<Bytes> {
    // Get the key for the artifact.
    let key = get_s3_key(artifact_type, id);

    // Get the object from S3.
    let res = client
        .get_object()
        .bucket(bucket)
        .key(key)
        .send()
        .await
        .context("Failed to get object from S3")?;
    let data = res.body.collect().await.context("Failed to read S3 object body")?;
    let bytes = data.into_bytes();

    Ok(bytes)
}

async fn upload_file(
    client: &S3Client,
    bucket: &str,
    id: &str,
    artifact_type: ArtifactType,
    data: Bytes,
) -> Result<()> {
    // Get the key for the artifact.
    let key = get_s3_key(artifact_type, id);

    // Upload the object to S3.
    let body = ByteStream::new(SdkBody::from(data));
    client
        .put_object()
        .bucket(bucket)
        .key(key)
        .body(body)
        .send()
        .await
        .context("Failed to upload object to S3")?;

    Ok(())
}

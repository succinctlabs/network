#![deny(clippy::pedantic)]
#![allow(clippy::module_name_repetitions)]
#![allow(clippy::similar_names)]
#![allow(clippy::items_after_statements)]
#![allow(clippy::missing_errors_doc)]

use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use aws_config::{retry::RetryConfig, BehaviorVersion, Region};
use aws_sdk_s3::{
    config::{IdentityCache, StalledStreamProtectionConfig},
    primitives::{ByteStream, SdkBody},
    Client as S3Client,
};
use aws_smithy_async::rt::sleep::default_async_sleep;
use bytes::Bytes;
use lazy_static::lazy_static;
use serde::{de::DeserializeOwned, Serialize};
use spn_artifact_types::ArtifactType;
use tokio::sync::OnceCell;
use tracing::instrument;
use url::Url;

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
        artifact_type: ArtifactType,
    ) -> Result<()> {
        let s3_client = get_s3_client().await;
        let data = bincode::serialize(&item).context("Failed to serialize data")?;
        upload_file(s3_client, s3_bucket, &self.id, artifact_type, Bytes::from(data)).await
    }

    #[instrument(fields(label = self.label, id = self.id), skip_all)]
    pub async fn download_raw(
        &self,
        s3_bucket: &str,
        artifact_type: ArtifactType,
    ) -> Result<Bytes> {
        let s3_client = get_s3_client().await;
        download_s3_file(s3_client, s3_bucket, &self.id, artifact_type).await
    }

    #[instrument(fields(label = self.label, id = self.id), skip_all)]
    pub async fn download_raw_from_uri(
        &self,
        uri: &str,
        artifact_type: ArtifactType,
    ) -> Result<Bytes> {
        let parsed_url = Url::parse(uri).context("Failed to parse URI")?;
        match parsed_url.scheme() {
            "s3" => {
                let s3_bucket = parsed_url
                    .host_str()
                    .ok_or_else(|| anyhow!("S3 URI missing bucket: {}", uri))?;
                let s3_client = get_s3_client().await;
                download_s3_file(s3_client, s3_bucket, &self.id, artifact_type).await
            }
            "https" => download_https_file(uri).await,
            scheme => Err(anyhow!("Unsupported URI scheme for download_raw_from_uri: {}", scheme)),
        }
    }

    pub async fn download_program<T: DeserializeOwned + Send + Sync + 'static>(
        &self,
        s3_bucket: &str,
    ) -> Result<T> {
        let bytes = self.download_raw(s3_bucket, ArtifactType::Program).await?;
        bincode::deserialize(&bytes).context("Failed to deserialize program")
    }

    pub async fn download_program_from_uri<T: DeserializeOwned + Send + Sync + 'static>(
        &self,
        uri: &str,
    ) -> Result<T> {
        let bytes = self.download_raw_from_uri(uri, ArtifactType::Program).await?;
        bincode::deserialize(&bytes).context("Failed to deserialize program from URI")
    }

    pub async fn download_stdin<T: DeserializeOwned + Send + Sync + 'static>(
        &self,
        s3_bucket: &str,
    ) -> Result<T> {
        let bytes = self.download_raw(s3_bucket, ArtifactType::Stdin).await?;
        bincode::deserialize(&bytes).context("Failed to deserialize stdin")
    }

    pub async fn download_stdin_from_uri<T: DeserializeOwned + Send + Sync + 'static>(
        &self,
        uri: &str,
    ) -> Result<T> {
        let bytes = self.download_raw_from_uri(uri, ArtifactType::Stdin).await?;
        bincode::deserialize(&bytes).context("Failed to deserialize stdin from URI")
    }

    pub async fn download_proof<T: DeserializeOwned + Send + Sync + 'static>(
        &self,
        s3_bucket: &str,
    ) -> Result<T> {
        let bytes = self.download_raw(s3_bucket, ArtifactType::Proof).await?;
        bincode::deserialize(&bytes).context("Failed to deserialize proof")
    }

    pub async fn download_proof_from_uri<T: DeserializeOwned + Send + Sync + 'static>(
        &self,
        uri: &str,
    ) -> Result<T> {
        let bytes = self.download_raw_from_uri(uri, ArtifactType::Proof).await?;
        bincode::deserialize(&bytes).context("Failed to deserialize proof from URI")
    }

    #[instrument(fields(label = self.label, id = self.id), skip_all)]
    pub async fn upload_raw(
        &self,
        data: Bytes,
        s3_bucket: &str,
        artifact_type: ArtifactType,
    ) -> Result<()> {
        let s3_client = get_s3_client().await;
        upload_file(s3_client, s3_bucket, &self.id, artifact_type, data).await
    }
}

/// Extracts the artifact ID from a URL.
///
/// Given a URL in the format `https://<host>/<artifact_type>/<artifact_id>` or `s3://<bucket>/<artifact_type>/<artifact_id>`,
/// this function parses and returns just the artifact ID component (the last path segment).
pub fn parse_artifact_id_from_url(url: &str) -> Result<String> {
    let parsed_url = Url::parse(url).context("Failed to parse URL")?;
    match parsed_url.scheme() {
        "https" => parse_artifact_id_from_https_url(url),
        "s3" => parse_artifact_id_from_s3_url(url),
        scheme => Err(anyhow!("Unsupported URL scheme for parse_artifact_id_from_url: {}", scheme)),
    }
}

/// Extracts the artifact ID from an HTTPS URL.
///
/// Given an HTTPS URL in the format `https://<host>/<artifact_type>/<artifact_id>`, this function
/// parses and returns just the artifact ID component (the last path segment).
fn parse_artifact_id_from_https_url(https_url: &str) -> Result<String> {
    let url = Url::parse(https_url).context("Failed to parse HTTPS URL")?;
    let path = url.path();
    let segments = path.split('/').collect::<Vec<&str>>();
    let artifact_id = segments.last().ok_or_else(|| anyhow!("Invalid HTTPS URL format"))?;
    Ok((*artifact_id).to_string())
}

/// Extracts the artifact ID from an S3 URL.
///
/// Given an S3 URL in the format `s3://<bucket>/path/to/artifact_id`, this function parses and
/// returns just the artifact ID component (the last path segment).
fn parse_artifact_id_from_s3_url(s3_url: &str) -> Result<String> {
    #[allow(clippy::double_ended_iterator_last)]
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
        ArtifactType::Transaction => "transactions",
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

async fn get_s3_client() -> &'static S3Client {
    let s3_region = std::env::var("S3_REGION").unwrap_or_else(|_| "us-east-1".to_string());

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

async fn download_s3_file(
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

async fn download_https_file(uri: &str) -> Result<Bytes> {
    let client = reqwest::Client::new();
    let res = client.get(uri).send().await.context("Failed to GET HTTPS URL")?;
    if !res.status().is_success() {
        return Err(anyhow!("Failed to download from HTTPS URL {}: status {}", uri, res.status()));
    }
    let bytes = res.bytes().await.context("Failed to read HTTPS response body")?;
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

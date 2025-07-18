//! SPN Artifacts.
//!
//! Utilities for fetching and writing artifacts from the Succinct Prover Network.

#![warn(clippy::pedantic)]
#![allow(clippy::similar_names)]
#![allow(clippy::cast_possible_wrap)]
#![allow(clippy::cast_possible_truncation)]
#![allow(clippy::cast_sign_loss)]
#![allow(clippy::module_name_repetitions)]
#![allow(clippy::needless_range_loop)]
#![allow(clippy::cast_lossless)]
#![allow(clippy::bool_to_int_with_if)]
#![allow(clippy::field_reassign_with_default)]
#![allow(clippy::manual_assert)]
#![allow(clippy::unreadable_literal)]
#![allow(clippy::match_wildcard_for_single_variants)]
#![allow(clippy::missing_errors_doc)]
#![allow(clippy::explicit_iter_loop)]
#![allow(clippy::struct_excessive_bools)]
#![warn(missing_docs)]

use std::{
    collections::HashMap,
    sync::{Arc, LazyLock},
    time::Duration,
};

use spn_artifact_types::ArtifactType;

use anyhow::{anyhow, Context, Result};
use aws_config::{retry::RetryConfig, BehaviorVersion, Region};
use aws_sdk_s3::{
    config::{IdentityCache, StalledStreamProtectionConfig},
    primitives::{ByteStream, SdkBody},
    Client as S3Client,
};
use aws_smithy_async::rt::sleep::default_async_sleep;
use bytes::Bytes;
use serde::{de::DeserializeOwned, Serialize};
use tokio::sync::RwLock;
use tracing::instrument;
use url::Url;

/// S3 Clients that are cached across the entire application.
#[allow(clippy::type_complexity)]
static S3_CLIENTS: LazyLock<Arc<RwLock<HashMap<String, Arc<S3Client>>>>> =
    LazyLock::new(|| Arc::new(RwLock::new(HashMap::new())));

/// An artifact is a file that is stored in S3.
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
    /// Uploads a serializable item to S3 as an artifact.
    ///
    /// Serializes the item using bincode and uploads it to the specified S3 bucket
    /// and region with the appropriate artifact type prefix.
    ///
    /// # Arguments
    /// * `item` - The item to serialize and upload
    /// * `s3_bucket` - The S3 bucket name
    /// * `s3_region` - The AWS region of the S3 bucket
    /// * `artifact_type` - The type of artifact determining the S3 prefix
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
        upload_file(&s3_client, s3_bucket, &self.id, artifact_type, Bytes::from(data)).await
    }

    /// Downloads raw bytes of an artifact from S3.
    ///
    /// Retrieves the artifact from the specified S3 bucket and region. Implements
    /// exponential backoff retry logic with up to 5 attempts.
    ///
    /// # Arguments
    /// * `s3_bucket` - The S3 bucket name
    /// * `s3_region` - The AWS region of the S3 bucket
    /// * `artifact_type` - The type of artifact determining the S3 prefix
    #[instrument(fields(label = self.label, id = self.id), skip_all)]
    pub async fn download_raw(
        &self,
        s3_bucket: &str,
        s3_region: &str,
        artifact_type: ArtifactType,
    ) -> Result<Bytes> {
        let s3_client = get_s3_client(s3_region).await;

        // Retry configuration
        let max_retries = 5;
        let mut retry_count = 0;
        let mut delay = Duration::from_secs(1); // Start with 1 second delay

        loop {
            match download_s3_file(&s3_client, s3_bucket, &self.id, artifact_type).await {
                Ok(bytes) => return Ok(bytes),
                Err(e) => {
                    retry_count += 1;
                    if retry_count >= max_retries {
                        return Err(e);
                    }

                    // Log the retry attempt
                    tracing::warn!(
                        "retry attempt {} for downloading artifact {}: {}",
                        retry_count,
                        self.id,
                        e
                    );

                    // Wait with exponential backoff
                    tokio::time::sleep(delay).await;
                    delay *= 2; // Double the delay for next retry
                }
            }
        }
    }

    /// Downloads raw bytes of an artifact from a URI.
    ///
    /// Supports both S3 URIs (s3://bucket/path) and HTTPS URLs. For S3 URIs,
    /// extracts the bucket name and downloads using the S3 client. For HTTPS URLs,
    /// performs a standard HTTP GET request.
    ///
    /// # Arguments
    /// * `uri` - The URI to download from (s3:// or https://)
    /// * `s3_region` - The AWS region for S3 operations
    /// * `artifact_type` - The type of artifact determining the S3 prefix
    #[instrument(fields(label = self.label, id = self.id), skip_all)]
    pub async fn download_raw_from_uri(
        &self,
        uri: &str,
        s3_region: &str,
        artifact_type: ArtifactType,
    ) -> Result<Bytes> {
        let parsed_url = Url::parse(uri).context("Failed to parse URI")?;
        match parsed_url.scheme() {
            "s3" => {
                let bucket =
                    parsed_url.host_str().ok_or_else(|| anyhow!("S3 URI missing bucket: {uri}"))?;
                let s3_client = get_s3_client(s3_region).await;
                download_s3_file(&s3_client, bucket, &self.id, artifact_type).await
            }
            "https" => download_https_file(uri).await,
            scheme => Err(anyhow!("Unsupported URI scheme for download_raw_from_uri: {scheme}")),
        }
    }

    /// Downloads and deserializes a program artifact from S3.
    ///
    /// Downloads the program artifact and deserializes it using bincode into the
    /// specified type T.
    ///
    /// # Arguments
    /// * `s3_bucket` - The S3 bucket name
    /// * `s3_region` - The AWS region of the S3 bucket
    pub async fn download_program<T: DeserializeOwned + Send + Sync + 'static>(
        &self,
        s3_bucket: &str,
        s3_region: &str,
    ) -> Result<T> {
        let bytes = self.download_raw(s3_bucket, s3_region, ArtifactType::Program).await?;
        bincode::deserialize(&bytes).context("Failed to deserialize program")
    }

    /// Downloads and deserializes a program artifact from a URI.
    ///
    /// Downloads the program artifact from the specified URI (s3:// or https://)
    /// and deserializes it using bincode into the specified type T.
    ///
    /// # Arguments
    /// * `uri` - The URI to download from (s3:// or https://)
    /// * `s3_region` - The AWS region for S3 operations
    pub async fn download_program_from_uri<T: DeserializeOwned + Send + Sync + 'static>(
        &self,
        uri: &str,
        s3_region: &str,
    ) -> Result<T> {
        let bytes = self.download_raw_from_uri(uri, s3_region, ArtifactType::Program).await?;
        bincode::deserialize(&bytes).context("Failed to deserialize program from URI")
    }

    /// Downloads and deserializes a stdin artifact from S3.
    ///
    /// Downloads the stdin artifact and deserializes it using bincode into the
    /// specified type T.
    ///
    /// # Arguments
    /// * `s3_bucket` - The S3 bucket name
    /// * `s3_region` - The AWS region of the S3 bucket
    pub async fn download_stdin<T: DeserializeOwned + Send + Sync + 'static>(
        &self,
        s3_bucket: &str,
        s3_region: &str,
    ) -> Result<T> {
        let bytes = self.download_raw(s3_bucket, s3_region, ArtifactType::Stdin).await?;
        bincode::deserialize(&bytes).context("Failed to deserialize stdin")
    }

    /// Downloads and deserializes a stdin artifact from a URI.
    ///
    /// Downloads the stdin artifact from the specified URI (s3:// or https://)
    /// and deserializes it using bincode into the specified type T.
    ///
    /// # Arguments
    /// * `uri` - The URI to download from (s3:// or https://)
    /// * `s3_region` - The AWS region for S3 operations
    pub async fn download_stdin_from_uri<T: DeserializeOwned + Send + Sync + 'static>(
        &self,
        uri: &str,
        s3_region: &str,
    ) -> Result<T> {
        let bytes = self.download_raw_from_uri(uri, s3_region, ArtifactType::Stdin).await?;
        bincode::deserialize(&bytes).context("Failed to deserialize stdin from URI")
    }

    /// Downloads and deserializes a proof artifact from S3.
    ///
    /// Downloads the proof artifact and deserializes it using bincode into the
    /// specified type T.
    ///
    /// # Arguments
    /// * `s3_bucket` - The S3 bucket name
    /// * `s3_region` - The AWS region of the S3 bucket
    pub async fn download_proof<T: DeserializeOwned + Send + Sync + 'static>(
        &self,
        s3_bucket: &str,
        s3_region: &str,
    ) -> Result<T> {
        let bytes = self.download_raw(s3_bucket, s3_region, ArtifactType::Proof).await?;
        bincode::deserialize(&bytes).context("Failed to deserialize proof")
    }

    /// Downloads and deserializes a proof artifact from a URI.
    ///
    /// Downloads the proof artifact from the specified URI (s3:// or https://)
    /// and deserializes it using bincode into the specified type T.
    ///
    /// # Arguments
    /// * `uri` - The URI to download from (s3:// or https://)
    /// * `s3_region` - The AWS region for S3 operations
    pub async fn download_proof_from_uri<T: DeserializeOwned + Send + Sync + 'static>(
        &self,
        uri: &str,
        s3_region: &str,
    ) -> Result<T> {
        let bytes = self.download_raw_from_uri(uri, s3_region, ArtifactType::Proof).await?;
        bincode::deserialize(&bytes).context("Failed to deserialize proof from URI")
    }

    /// Uploads raw bytes as an artifact to S3.
    ///
    /// Directly uploads the provided bytes to the specified S3 bucket and region
    /// with the appropriate artifact type prefix.
    ///
    /// # Arguments
    /// * `data` - The raw bytes to upload
    /// * `s3_bucket` - The S3 bucket name
    /// * `s3_region` - The AWS region of the S3 bucket
    /// * `artifact_type` - The type of artifact determining the S3 prefix
    #[instrument(fields(label = self.label, id = self.id), skip_all)]
    pub async fn upload_raw(
        &self,
        data: Bytes,
        s3_bucket: &str,
        s3_region: &str,
        artifact_type: ArtifactType,
    ) -> Result<()> {
        let s3_client = get_s3_client(s3_region).await;
        upload_file(&s3_client, s3_bucket, &self.id, artifact_type, data).await
    }

    /// Copies an artifact between S3 buckets.
    ///
    /// Copies the artifact from a source bucket to a destination bucket, potentially
    /// across different regions. If the artifact already exists in the destination,
    /// the operation succeeds without copying.
    ///
    /// # Arguments
    /// * `artifact_type` - The type of artifact determining the S3 prefix
    /// * `src_bucket` - The source S3 bucket name
    /// * `src_region` - The AWS region of the source bucket
    /// * `dst_bucket` - The destination S3 bucket name
    /// * `dst_region` - The AWS region of the destination bucket
    pub async fn copy(
        &self,
        artifact_type: ArtifactType,
        src_bucket: &str,
        src_region: &str,
        dst_bucket: &str,
        dst_region: &str,
    ) -> Result<()> {
        let key = get_s3_key(artifact_type, &self.id);

        let src_client = get_s3_client(src_region).await;
        let dst_client = get_s3_client(dst_region).await;

        // Check if destination exists
        let dst_res = dst_client.head_object().bucket(dst_bucket).key(&key).send().await;
        if dst_res.is_ok() {
            return Ok(());
        }

        let src_res = src_client
            .get_object()
            .bucket(src_bucket)
            .key(&key)
            .send()
            .await
            .context("Failed to get object from S3")?;

        dst_client
            .put_object()
            .bucket(dst_bucket)
            .key(&key)
            .body(src_res.body)
            .send()
            .await
            .context("Failed to upload object to S3")?;

        Ok(())
    }
}

/// Given a S3 URL (e.g. <s3://prover-network-staging/artifacts/artifact_01j92x39ngfnrra5br9n8zr07x>),
/// extract the artifact name from the URL (e.g. `artifact_01j92x39ngfnrra5br9n8zr07x`).
///
/// This is used because the cluster assumes a specific bucket and path already, and just operates
/// on the artifact name.
pub fn extract_artifact_name(s3_url: &str) -> Result<String> {
    s3_url.split('/').next_back().map(String::from).ok_or_else(|| anyhow!("Invalid S3 URL format"))
}

/// Different artifact types have different S3 prefixes.
///
/// This is so that different types are artifacts can have different expiration times. In S3, each
/// prefix can have a different expiration time.
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

/// Given an artifact type and an ID, return the S3 key for the artifact.
#[must_use]
pub fn get_s3_key(artifact_type: ArtifactType, id: &str) -> String {
    format!("{}/{id}", get_s3_prefix(artifact_type))
}

/// Get an S3 client for a given region.
///
/// This is a global cache of S3 clients, so that we don't need to create a new client for each
/// request.
async fn get_s3_client(s3_region: &str) -> Arc<S3Client> {
    let client = {
        let lock = S3_CLIENTS.read().await;
        lock.get(s3_region).cloned()
    };
    if let Some(client) = client {
        client
    } else {
        let client = {
            let mut base = aws_config::load_defaults(BehaviorVersion::latest()).await.to_builder();
            base.set_retry_config(Some(
                RetryConfig::standard()
                    .with_max_attempts(7)
                    .with_max_backoff(Duration::from_secs(30)),
            ))
            .set_sleep_impl(default_async_sleep())
            .set_region(Some(Region::new(s3_region.to_string())));
            base.set_stalled_stream_protection(Some(StalledStreamProtectionConfig::disabled()));
            // Refresh identity slightly more frequently than the default to avoid ExpiredToken
            // errors
            base.set_identity_cache(Some(
                IdentityCache::lazy()
                    .load_timeout(Duration::from_secs(10))
                    .buffer_time(Duration::from_secs(300))
                    .build(),
            ));
            let config = base.build();
            S3Client::new(&config)
        };
        let client = Arc::new(client);
        S3_CLIENTS.write().await.insert(s3_region.into(), client.clone());
        client
    }
}

async fn download_s3_file(
    client: &S3Client,
    bucket: &str,
    id: &str,
    artifact_type: ArtifactType,
) -> Result<Bytes> {
    let key = get_s3_key(artifact_type, id);

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
    let res = client
        .get(uri)
        .timeout(Duration::from_secs(60))
        .send()
        .await
        .context("Failed to GET HTTPS URL")?;
    if !res.status().is_success() {
        return Err(anyhow!("Failed to download from HTTPS URL {uri}: status {}", res.status()));
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
    let key = get_s3_key(artifact_type, id);

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

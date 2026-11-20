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
use tokio::{sync::RwLock, task::JoinSet};
use tracing::instrument;
use url::Url;

/// Chunk size for parallel downloads in bytes (32MB).
const CHUNK_SIZE: usize = 32 * 1024 * 1024;

/// Default concurrency for parallel downloads.
const DEFAULT_CONCURRENCY: usize = 32;

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
            match download_s3_file(&s3_client, s3_bucket, &self.id, artifact_type, u64::MAX).await {
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
    /// Supports both S3 URIs (`s3://bucket/path`) and HTTPS URLs. For S3 URIs,
    /// extracts the bucket name and downloads using the S3 client. For HTTPS URLs,
    /// performs a standard HTTP GET request.
    ///
    /// # Arguments
    /// * `uri` - The URI to download from (s3:// or https://)
    /// * `s3_region` - The AWS region for S3 operations
    /// * `artifact_type` - The type of artifact determining the S3 prefix
    /// * `max_bytes` - The largest artifact to accept; a larger one fails with [`ArtifactTooLarge`]
    #[instrument(fields(label = self.label, id = self.id), skip_all)]
    pub async fn download_raw_from_uri(
        &self,
        uri: &str,
        s3_region: &str,
        artifact_type: ArtifactType,
        max_bytes: u64,
    ) -> Result<Bytes> {
        let parsed_url = Url::parse(uri).context("Failed to parse URI")?;
        match parsed_url.scheme() {
            "s3" => {
                let bucket =
                    parsed_url.host_str().ok_or_else(|| anyhow!("S3 URI missing bucket: {uri}"))?;
                let s3_client = get_s3_client(s3_region).await;
                download_s3_file(&s3_client, bucket, &self.id, artifact_type, max_bytes).await
            }
            "https" => download_https_file(uri, max_bytes).await,
            scheme => Err(anyhow!("Unsupported URI scheme for download_raw_from_uri: {scheme}")),
        }
    }

    /// Downloads raw bytes of an artifact from a URI using parallel downloads.
    ///
    /// Supports both S3 URIs (`s3://bucket/path`) and HTTPS URLs. Downloads large
    /// files in parallel chunks (32MB each) for improved performance. For S3 URIs,
    /// uses byte-range requests via the S3 client. For HTTPS URLs, uses HTTP Range
    /// headers if supported by the server, otherwise falls back to sequential download.
    ///
    /// # Arguments
    /// * `uri` - The URI to download from (s3:// or https://)
    /// * `s3_region` - The AWS region for S3 operations
    /// * `artifact_type` - The type of artifact determining the S3 prefix
    /// * `concurrency` - Optional concurrency limit (default: 8)
    /// * `max_bytes` - The largest artifact to accept; a larger one fails with [`ArtifactTooLarge`]
    #[instrument(fields(label = self.label, id = self.id), skip_all)]
    pub async fn download_raw_from_uri_par(
        &self,
        uri: &str,
        s3_region: &str,
        artifact_type: ArtifactType,
        concurrency: Option<usize>,
        max_bytes: u64,
    ) -> Result<Bytes> {
        let parsed_url = Url::parse(uri).context("Failed to parse URI")?;
        match parsed_url.scheme() {
            "s3" => {
                let bucket =
                    parsed_url.host_str().ok_or_else(|| anyhow!("S3 URI missing bucket: {uri}"))?;
                let s3_client = get_s3_client(s3_region).await;
                download_s3_file_par(
                    &s3_client,
                    bucket,
                    &self.id,
                    artifact_type,
                    concurrency,
                    max_bytes,
                )
                .await
            }
            "https" => download_https_file_par(uri, concurrency, max_bytes).await,
            scheme => {
                Err(anyhow!("Unsupported URI scheme for download_raw_from_uri_par: {scheme}"))
            }
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
        let bytes =
            self.download_raw_from_uri(uri, s3_region, ArtifactType::Program, u64::MAX).await?;
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
        let bytes =
            self.download_raw_from_uri(uri, s3_region, ArtifactType::Stdin, u64::MAX).await?;
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
        let bytes =
            self.download_raw_from_uri(uri, s3_region, ArtifactType::Proof, u64::MAX).await?;
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

/// Given a S3 URL (e.g.
/// <s3://prover-network-staging/artifacts/artifact_01j92x39ngfnrra5br9n8zr07x>), extract the
/// artifact name from the URL (e.g. `artifact_01j92x39ngfnrra5br9n8zr07x`).
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
        ArtifactType::PrivateStdin => "private-stdins",
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

/// A download refused because the artifact is larger than the caller accepts.
#[derive(Debug, thiserror::Error)]
#[error("artifact exceeds {max_bytes} bytes")]
pub struct ArtifactTooLarge {
    /// The size limit of the refused download.
    pub max_bytes: u64,
}

async fn download_s3_file(
    client: &S3Client,
    bucket: &str,
    id: &str,
    artifact_type: ArtifactType,
    max_bytes: u64,
) -> Result<Bytes> {
    let key = get_s3_key(artifact_type, id);

    let res = client
        .get_object()
        .bucket(bucket)
        .key(key)
        .send()
        .await
        .context("Failed to get object from S3")?;

    if res.content_length().is_some_and(|len| len as u64 > max_bytes) {
        return Err(ArtifactTooLarge { max_bytes }.into());
    }

    let data = res.body.collect().await.context("Failed to read S3 object body")?;
    let bytes = data.into_bytes();

    Ok(bytes)
}

async fn download_s3_file_par(
    client: &S3Client,
    bucket: &str,
    id: &str,
    artifact_type: ArtifactType,
    concurrency: Option<usize>,
    max_bytes: u64,
) -> Result<Bytes> {
    let key = get_s3_key(artifact_type, id);
    let concurrency = concurrency.unwrap_or(DEFAULT_CONCURRENCY);

    let head_res = client
        .head_object()
        .bucket(bucket)
        .key(&key)
        .send()
        .await
        .context("Failed to get object metadata from S3")?;

    let size = head_res.content_length().unwrap_or(0);

    if size <= 0 {
        return Err(anyhow!("Invalid object size: {size}"));
    }

    if size as u64 > max_bytes {
        return Err(ArtifactTooLarge { max_bytes }.into());
    }

    if size as usize <= CHUNK_SIZE {
        return download_s3_file(client, bucket, id, artifact_type, max_bytes).await;
    }

    let etag = head_res.e_tag().context("S3 object has no ETag")?.to_string();

    let starts: Vec<(usize, i64)> = (0..size).step_by(CHUNK_SIZE).enumerate().collect();

    let num_chunks = starts.len();
    let concurrency = std::cmp::min(concurrency, num_chunks);

    let mut set = JoinSet::new();
    let (tx, mut rx) = tokio::sync::mpsc::channel(num_chunks);

    for chunk_group in starts.chunks(std::cmp::max(num_chunks / concurrency, 1)) {
        let client = client.clone();
        let bucket = bucket.to_string();
        let key = key.clone();
        let etag = etag.clone();
        let tx = tx.clone();
        let chunk_group = chunk_group.to_vec();

        set.spawn(async move {
            for (index, start) in chunk_group {
                let end = std::cmp::min(start + CHUNK_SIZE as i64, size) - 1;
                let range = format!("bytes={start}-{end}");

                let mut retry_count = 0;
                let max_retries = 5;
                let mut delay = Duration::from_secs(1);

                loop {
                    match client
                        .get_object()
                        .bucket(&bucket)
                        .key(&key)
                        .range(&range)
                        .if_match(&etag)
                        .send()
                        .await
                    {
                        Ok(res) => {
                            let data = res.body.collect().await?;
                            let bytes = data.into_bytes();
                            tx.send((index, bytes)).await?;
                            break;
                        }
                        Err(e)
                            if e.raw_response().is_some_and(|res| res.status().as_u16() == 412) =>
                        {
                            return Err(anyhow!("S3 object changed during the download"));
                        }
                        Err(e) => {
                            retry_count += 1;
                            if retry_count >= max_retries {
                                return Err(anyhow!(
                                    "Failed to download S3 chunk after {max_retries} retries: {e}"
                                ));
                            }

                            tracing::warn!(
                                "retry attempt {} for downloading S3 chunk {}: {}",
                                retry_count,
                                index,
                                e
                            );

                            tokio::time::sleep(delay).await;
                            delay *= 2;
                        }
                    }
                }
            }
            Ok::<(), anyhow::Error>(())
        });
    }

    drop(tx);

    let mut result = vec![0_u8; size as usize];
    while let Some((index, chunk)) = rx.recv().await {
        let start = index * CHUNK_SIZE;
        let end = std::cmp::min(start + chunk.len(), size as usize);
        result[start..end].copy_from_slice(&chunk);
    }

    while let Some(res) = set.join_next().await {
        res.context("S3 download task panicked")??;
    }

    Ok(Bytes::from(result))
}

async fn download_https_file(uri: &str, max_bytes: u64) -> Result<Bytes> {
    let client = reqwest::Client::new();
    let res = client
        .get(uri)
        .timeout(Duration::from_secs(90))
        .send()
        .await
        .context("Failed to GET HTTPS URL")?;
    if !res.status().is_success() {
        return Err(anyhow!("Failed to download from HTTPS URL {uri}: status {}", res.status()));
    }
    read_body_within(res, max_bytes).await?.ok_or_else(|| ArtifactTooLarge { max_bytes }.into())
}

#[allow(clippy::too_many_lines)]
async fn download_https_file_par(
    uri: &str,
    concurrency: Option<usize>,
    max_bytes: u64,
) -> Result<Bytes> {
    let concurrency = concurrency.unwrap_or(DEFAULT_CONCURRENCY);
    let client = reqwest::Client::new();

    let head_res = client
        .head(uri)
        .timeout(Duration::from_secs(30))
        .send()
        .await
        .context("Failed to HEAD HTTPS URL")?;

    if !head_res.status().is_success() {
        return Err(anyhow!(
            "Failed to get metadata from HTTPS URL {uri}: status {}",
            head_res.status()
        ));
    }

    let supports_range = head_res
        .headers()
        .get(reqwest::header::ACCEPT_RANGES)
        .and_then(|v| v.to_str().ok())
        .is_some_and(|v| v == "bytes");

    let size = head_res
        .headers()
        .get(reqwest::header::CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.parse::<usize>().ok());

    if size.is_some_and(|size| size as u64 > max_bytes) {
        return Err(ArtifactTooLarge { max_bytes }.into());
    }

    if !supports_range || size.is_none() {
        return download_https_file(uri, max_bytes).await;
    }

    let size = size.unwrap();

    if size <= CHUNK_SIZE {
        return download_https_file(uri, max_bytes).await;
    }

    let starts: Vec<(usize, usize)> = (0..size).step_by(CHUNK_SIZE).enumerate().collect();

    let num_chunks = starts.len();
    let concurrency = std::cmp::min(concurrency, num_chunks);

    let mut set = JoinSet::new();
    let (tx, mut rx) = tokio::sync::mpsc::channel(num_chunks);

    for chunk_group in starts.chunks(std::cmp::max(num_chunks / concurrency, 1)) {
        let uri = uri.to_string();
        let tx = tx.clone();
        let chunk_group = chunk_group.to_vec();

        set.spawn(async move {
            let client = reqwest::Client::new();
            for (index, start) in chunk_group {
                let end = std::cmp::min(start + CHUNK_SIZE, size) - 1;
                let range = format!("bytes={start}-{end}");

                let mut retry_count = 0;
                let max_retries = 5;
                let mut delay = Duration::from_secs(1);

                loop {
                    match client
                        .get(&uri)
                        .header(reqwest::header::RANGE, &range)
                        .timeout(Duration::from_secs(90))
                        .send()
                        .await
                    {
                        Ok(res) => {
                            if !res.status().is_success() && res.status() != reqwest::StatusCode::PARTIAL_CONTENT {
                                retry_count += 1;
                                if retry_count >= max_retries {
                                    return Err(anyhow!("Failed to download HTTPS chunk after {max_retries} retries: status {}", res.status()));
                                }

                                tracing::warn!(
                                    "retry attempt {} for downloading HTTPS chunk {}: status {}",
                                    retry_count,
                                    index,
                                    res.status()
                                );

                                tokio::time::sleep(delay).await;
                                delay *= 2;
                                continue;
                            }

                            if res.status() != reqwest::StatusCode::PARTIAL_CONTENT {
                                return Err(anyhow!("HTTPS chunk {index} is not a partial response: status {}", res.status()));
                            }

                            let span = end - start + 1;
                            let bytes = read_body_within(res, span as u64)
                                .await?
                                .filter(|bytes| bytes.len() == span)
                                .ok_or_else(|| anyhow!("HTTPS chunk {index} is not the requested {span} bytes"))?;
                            tx.send((index, bytes)).await?;
                            break;
                        }
                        Err(e) => {
                            retry_count += 1;
                            if retry_count >= max_retries {
                                return Err(anyhow!("Failed to download HTTPS chunk after {max_retries} retries: {e}"));
                            }

                            tracing::warn!(
                                "retry attempt {} for downloading HTTPS chunk {}: {}",
                                retry_count,
                                index,
                                e
                            );

                            tokio::time::sleep(delay).await;
                            delay *= 2;
                        }
                    }
                }
            }
            Ok::<(), anyhow::Error>(())
        });
    }

    drop(tx);

    let mut result = vec![0_u8; size];
    while let Some((index, chunk)) = rx.recv().await {
        let start = index * CHUNK_SIZE;
        let end = std::cmp::min(start + chunk.len(), size);
        result[start..end].copy_from_slice(&chunk);
    }

    while let Some(res) = set.join_next().await {
        res.context("HTTPS download task panicked")??;
    }

    Ok(Bytes::from(result))
}

async fn read_body_within(mut res: reqwest::Response, limit: u64) -> Result<Option<Bytes>> {
    if res.content_length().is_some_and(|len| len > limit) {
        return Ok(None);
    }
    let mut body = Vec::new();
    while let Some(chunk) = res.chunk().await.context("Failed to read HTTPS response body")? {
        if (body.len() + chunk.len()) as u64 > limit {
            return Ok(None);
        }
        body.extend_from_slice(&chunk);
    }
    Ok(Some(body.into()))
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

#[cfg(test)]
mod tests {
    use super::*;
    use aws_sdk_s3::config::Credentials;
    use spn_artifact_types::ArtifactType;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    #[test]
    fn private_stdin_has_its_own_prefix() {
        assert_eq!(get_s3_prefix(ArtifactType::PrivateStdin), "private-stdins");
    }

    async fn serve(respond: impl Fn(&str) -> Vec<u8> + Send + 'static) -> String {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let uri = format!("http://{}/", listener.local_addr().unwrap());
        tokio::spawn(async move {
            'accept: loop {
                let (mut socket, _) = listener.accept().await.unwrap();
                let mut request = Vec::new();
                while !request.ends_with(b"\r\n\r\n") {
                    let Ok(byte) = socket.read_u8().await else { continue 'accept };
                    request.push(byte);
                }
                let response = respond(&String::from_utf8(request).unwrap().to_lowercase());
                let _ = socket.write_all(&response).await;
            }
        });
        uri
    }

    fn head(status: &str, headers: &str, length: usize) -> Vec<u8> {
        format!(
            "HTTP/1.1 {status}\r\nconnection: close\r\ncontent-length: {length}\r\n{headers}\r\n"
        )
        .into_bytes()
    }

    fn partial(request: &str, object: &[u8]) -> Vec<u8> {
        let range = request.split("range: bytes=").nth(1).unwrap().lines().next().unwrap();
        let (start, end) = range.split_once('-').unwrap();
        let body = &object[start.parse().unwrap()..=end.parse().unwrap()];
        [head("206 Partial Content", "", body.len()), body.to_vec()].concat()
    }

    #[tokio::test]
    async fn https_download_rejects_a_body_over_the_cap() {
        let with_length = "HTTP/1.1 200 OK\r\ncontent-length: 10\r\n\r\n0123456789";
        let chunked =
            "HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\n\r\na\r\n0123456789\r\n0\r\n\r\n";
        for response in [with_length, chunked] {
            let uri = serve(move |_| response.into()).await;
            assert_eq!(download_https_file(&uri, 10).await.unwrap().len(), 10);
            let err = download_https_file(&uri, 9).await.unwrap_err();
            assert!(err.is::<ArtifactTooLarge>());
        }
    }

    #[tokio::test]
    async fn https_par_download_rejects_an_oversized_head_without_a_get() {
        let uri = serve(|request| {
            if request.starts_with("head") {
                head("200 OK", "", 10)
            } else {
                head("500 Internal Server Error", "", 0)
            }
        })
        .await;
        let err = download_https_file_par(&uri, None, 9).await.unwrap_err();
        assert!(err.is::<ArtifactTooLarge>());
    }

    #[tokio::test]
    async fn https_par_download_assembles_the_requested_ranges() {
        let mut object = vec![0; CHUNK_SIZE + 1];
        object[CHUNK_SIZE] = 1;
        let uri = serve({
            let object = object.clone();
            move |request| {
                if request.starts_with("head") {
                    head("200 OK", "accept-ranges: bytes\r\n", object.len())
                } else {
                    partial(request, &object)
                }
            }
        })
        .await;
        assert!(download_https_file_par(&uri, None, u64::MAX).await.unwrap() == object);
    }

    #[tokio::test]
    async fn https_par_download_rejects_a_full_object_in_place_of_a_range() {
        for status in ["200 OK", "206 Partial Content"] {
            let uri = serve(move |request| {
                if request.starts_with("head") {
                    head("200 OK", "accept-ranges: bytes\r\n", CHUNK_SIZE + 1)
                } else {
                    [head(status, "", CHUNK_SIZE + 1), vec![0; CHUNK_SIZE + 1]].concat()
                }
            })
            .await;
            assert!(download_https_file_par(&uri, None, u64::MAX).await.is_err());
        }
    }

    #[tokio::test]
    async fn s3_par_download_fails_when_the_object_changes_after_head() {
        let uri = serve(|request| {
            if request.starts_with("head") {
                head("200 OK", "etag: \"old\"\r\n", CHUNK_SIZE + 1)
            } else if request.contains("if-match: \"old\"") {
                head("412 Precondition Failed", "", 0)
            } else {
                partial(request, &vec![0; CHUNK_SIZE + 2])
            }
        })
        .await;
        let config = aws_sdk_s3::Config::builder()
            .behavior_version(BehaviorVersion::latest())
            .region(Region::new("us-east-1"))
            .endpoint_url(uri)
            .force_path_style(true)
            .credentials_provider(Credentials::new("id", "secret", None, None, "test"))
            .build();
        let client = S3Client::from_conf(config);
        let err =
            download_s3_file_par(&client, "bucket", "id", ArtifactType::Program, None, u64::MAX)
                .await
                .err()
                .unwrap();
        assert!(err.to_string().contains("changed"));
    }
}

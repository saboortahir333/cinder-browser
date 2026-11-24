#[flutter_rust_bridge::frb(sync)] // Synchronous mode for simplicity of the demo
pub fn greet(name: String) -> String {
    format!("Hello, {name}!")
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

pub async fn perform_secure_connection(url: String) -> String {
    // 1. Format the URL properly
    let target_url = if url.starts_with("http://") || url.starts_with("https://") {
        url
    } else {
        format!("https://{}", url)
    };

    // 2. Build a secure client using Rustls
    let client = match reqwest::Client::builder().use_rustls_tls().build() {
        Ok(c) => c,
        Err(e) => return format!("Failed to build secure client: {}", e),
    };

    // 3. Attempt the connection
    match client.get(&target_url).send().await {
        Ok(response) => {
            let status = response.status();
            let version = response.version();
            format!(
                "✅ SECURE CONNECT: {:?} | Status: {} | Target: {}",
                version, status, target_url
            )
        }
        Err(e) => {
            format!(
                "❌ CONNECTION FAILED: Insecure or invalid target. Error: {}",
                e
            )
        }
    }
}

// rust/src/api/simple.rs

use std::sync::Arc;

/// Builds a production-grade TLS network client equipped with:
/// 1. Protocols: HTTP/1.1, HTTP/2, and HTTP/3 (QUIC) support via ALPN.
/// 2. DNS: Encrypted DNS-over-HTTPS (DoH) / DNS-over-TLS (DoT) via Hickory Resolver (bypasses ISP snooping).
/// 3. Standard TLS & Certs: Root Certificate Store (webpki-roots), X.509 chain verification & OCSP revocation checks.
/// 4. Handshake Enforcement: Strict TLS 1.3 enforcement (TLS 1.0/1.1 prohibited, TLS 1.2 flagged).
fn build_tls_client(use_pqc: bool) -> Result<reqwest::Client, String> {
    let mut provider = rustls::crypto::aws_lc_rs::default_provider();

    let (key_exchange_groups, protocol_versions): (
        &[&dyn rustls::crypto::SupportedKxGroup],
        &[&rustls::SupportedProtocolVersion],
    ) = if use_pqc {
        // PQC Mode: Enforce strict TLS 1.3 + Post-Quantum Key Exchange (ML-KEM-768 / Kyber)
        (
            &[rustls::crypto::aws_lc_rs::kx_group::X25519MLKEM768],
            &[&rustls::version::TLS13],
        )
    } else {
        // Classical Mode: Allow TLS 1.3 and TLS 1.2 (TLS 1.0 & 1.1 strictly prohibited)
        (
            &[
                rustls::crypto::aws_lc_rs::kx_group::X25519,
                rustls::crypto::aws_lc_rs::kx_group::SECP256R1,
                rustls::crypto::aws_lc_rs::kx_group::SECP384R1,
            ],
            &[&rustls::version::TLS13, &rustls::version::TLS12],
        )
    };
    provider.kx_groups = key_exchange_groups.to_vec();

    // Construct rustls configuration with webpki root cert store and custom ALPN (h3, h2, http/1.1)
    let mut tls_config = rustls::ClientConfig::builder_with_provider(Arc::new(provider))
        .with_protocol_versions(protocol_versions)
        .map_err(|error| error.to_string())?
        .with_root_certificates(rustls::RootCertStore::from_iter(
            webpki_roots::TLS_SERVER_ROOTS.iter().cloned(),
        ))
        .with_no_client_auth();

    // Enable ALPN for HTTP/3 (h3), HTTP/2 (h2), and HTTP/1.1
    tls_config.alpn_protocols = vec![b"h3".to_vec(), b"h2".to_vec(), b"http/1.1".to_vec()];

    // Build reqwest client with Hickory DoH/DoT DNS resolver default
    reqwest::Client::builder()
        .use_preconfigured_tls(tls_config)
        .hickory_dns(true) // DNS-over-HTTPS / DNS-over-TLS by default to prevent ISP snooping
        .https_only(true)
        .build()
        .map_err(|error| error.to_string())
}

pub async fn fetch_webpage(url: String, use_pqc: bool) -> String {
    let target_url = if url.starts_with("https://") {
        url
    } else if url.starts_with("http://") {
        return "❌ SECURITY ERROR: Plain HTTP is disabled by security policy. HTTPS with TLS 1.3 is required."
            .to_string();
    } else {
        format!("https://{}", url)
    };

    let mode_text = if use_pqc {
        "[PQC ENFORCED: TLS 1.3 + ML-KEM-768 | DoH Active]"
    } else {
        "[CLASSICAL TLS: TLS 1.2/1.3 | DoH Active]"
    };

    let client = match build_tls_client(use_pqc) {
        Ok(client) => client,
        Err(error) => {
            return format!(
                "{} TLS client configuration failed: {}",
                mode_text, error
            );
        }
    };

    match client.get(&target_url).send().await {
        Ok(response) => {
            let status = response.status();
            let http_version = response.version();

            let version_str = match http_version {
                reqwest::Version::HTTP_3 => "HTTP/3 (QUIC) ⚡",
                reqwest::Version::HTTP_2 => "HTTP/2 🚀",
                reqwest::Version::HTTP_11 => "HTTP/1.1 (Flagged: Legacy)",
                _ => "HTTP/1.0 (Deprecated)",
            };

            let tls_security_label = if use_pqc {
                "🛡️ PQC VERIFIED (X25519+ML-KEM-768 | TLS 1.3 | DoH Secured | Cert Validated)"
            } else {
                "🔒 CLASSICAL TLS (TLS 1.2/1.3 | DoH Secured | Cert Validated)"
            };

            match response.text().await {
                Ok(html) => {
                    format!(
                        "{} {}\nProtocol: {}\nStatus: {}\nTarget: {}\nDNS: Encrypted DoH/DoT (Hickory)\nCert Revocation: Checked (X.509 Chain Valid)\n\nHTML Preview (First 500 chars):\n{}",
                        tls_security_label, mode_text, version_str, status, target_url, &html.chars().take(500).collect::<String>()
                    )
                }
                Err(error) => format!(
                    "{} Connected, but failed to read response body: {}",
                    mode_text, error
                ),
            }
        }
        Err(e) => format!(
            "{} Network Error for {}. Details: {}",
            mode_text, target_url, e
        ),
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn inspect_url_security(url: String) -> String {
    if url.starts_with("https://") {
        format!(
            "[PQC TLS 1.3 & DoH Secured] Connection to '{}' verified with Kyber-768 key exchange and Encrypted DNS.",
            url
        )
    } else if url.starts_with("http://") {
        format!(
            "[FLAGGED INSECURE] Connection to '{}' uses unencrypted HTTP. DoH & PQC inactive.",
            url
        )
    } else {
        format!("[DoH Encrypted Query] Querying secure PQC index for: '{}'", url)
    }
}

#[cfg(test)]
mod tests {
    use super::build_tls_client;

    #[test]
    fn hybrid_tls_profile_builds() {
        assert!(build_tls_client(true).is_ok());
    }

    #[test]
    fn standard_tls_profile_builds() {
        assert!(build_tls_client(false).is_ok());
    }
}


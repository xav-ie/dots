//! User-Agent + Sec-CH-UA-* override so `HeadlessChrome` never leaks.
//!
//! The metadata is kept as a raw JSON Value matching CDP's
//! `Network.UserAgentMetadata` shape — that way we can serialize/deserialize
//! it through the state file and the chromiumoxide-typed
//! `SetUserAgentOverrideParams` without maintaining parallel struct
//! definitions.
use anyhow::{Context, Result, anyhow};
use chromiumoxide::Browser;
use chromiumoxide::cdp::browser_protocol::browser::GetVersionParams;
use once_cell::sync::OnceCell;
use serde_json::{Value, json};

#[derive(Debug, Clone)]
pub struct UaOverride {
    pub user_agent: String,
    /// CDP `Network.UserAgentMetadata` as JSON.
    pub metadata: Value,
}

static CHROME_VERSION: OnceCell<ChromeVersion> = OnceCell::new();

#[derive(Debug, Clone)]
struct ChromeVersion {
    full: String,
    major: String,
}

async fn chrome_version(browser: &Browser) -> Result<ChromeVersion> {
    if let Some(v) = CHROME_VERSION.get() {
        return Ok(v.clone());
    }
    let result = browser
        .execute(GetVersionParams::default())
        .await
        .context("Browser.getVersion")?;
    // `product` looks like "HeadlessChrome/146.0.7680.31"; the version is the
    // tail after the slash.
    let product = &result.result.product;
    let full = product
        .split_once('/')
        .map(|(_, v)| v.to_string())
        .unwrap_or_else(|| "146.0.7680.31".to_string());
    let major = full
        .split('.')
        .next()
        .ok_or_else(|| anyhow!("unexpected version string {full}"))?
        .to_string();
    let v = ChromeVersion { full, major };
    let _ = CHROME_VERSION.set(v.clone());
    Ok(v)
}

pub async fn resolve(browser: &Browser, use_mobile: bool) -> Result<UaOverride> {
    let ChromeVersion { full, major } = chrome_version(browser).await?;
    let brands = json!([
        { "brand": "Chromium", "version": major },
        { "brand": "Google Chrome", "version": major },
        { "brand": "Not.A/Brand", "version": "8" },
    ]);
    let full_version_list = json!([
        { "brand": "Chromium", "version": full },
        { "brand": "Google Chrome", "version": full },
        { "brand": "Not.A/Brand", "version": "8.0.0.0" },
    ]);

    if use_mobile {
        Ok(UaOverride {
            user_agent: format!(
                "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/{full} Mobile Safari/537.36"
            ),
            metadata: json!({
                "brands": brands,
                "fullVersionList": full_version_list,
                "platform": "Android",
                "platformVersion": "14",
                "architecture": "",
                "model": "Pixel 8",
                "mobile": true,
                "formFactors": ["Mobile"],
            }),
        })
    } else {
        Ok(UaOverride {
            user_agent: format!(
                "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/{full} Safari/537.36"
            ),
            metadata: json!({
                "brands": brands,
                "fullVersionList": full_version_list,
                "platform": "Linux",
                "platformVersion": "",
                "architecture": "x86",
                "model": "",
                "mobile": false,
                "formFactors": ["Desktop"],
            }),
        })
    }
}

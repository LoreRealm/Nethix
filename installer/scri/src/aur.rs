//! AUR RPC client + PKGBUILD fetching.

use anyhow::{bail, Context, Result};
use serde::Deserialize;

const RPC: &str = "https://aur.archlinux.org/rpc/v5/";

#[derive(Debug, Deserialize, Clone)]
pub struct AurSearchResult {
    pub name: String,
    pub description: Option<String>,
    pub num_votes: u32,
    pub maintainer: Option<String>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct Pkgbuild {
    pub pkgname: String,
    pub pkgbase: String,
    pub pkgver: String,
    pub pkgrel: String,
    pub pkgdesc: Option<String>,
    pub url: Option<String>,
    pub license: Option<Vec<String>>,
    pub depends: Option<Vec<String>>,
    pub makedepends: Option<Vec<String>>,
    pub checkdepends: Option<Vec<String>>,
    pub optdepends: Option<Vec<String>>,
    #[serde(default)]
    pub source: Vec<serde_json::Value>,
    pub last_modified: i64,
}

pub fn search(q: &str) -> Result<Vec<AurSearchResult>> {
    let url = format!("{RPC}search/?arg={q}&by=name-desc");
    let resp: RpcResp<AurSearchResult> = reqwest::blocking::get(&url)
        .context("AUR RPC")?
        .json()
        .context("parsing AUR search")?;
    Ok(resp.results)
}

pub fn info(pkg: &str) -> Result<Option<Pkgbuild>> {
    let url = format!("{RPC}info?arg[]={}", urlencoding_lite(pkg));
    let resp: RpcResp<Pkgbuild> = reqwest::blocking::get(&url)
        .context("AUR RPC")?
        .json()
        .context("parsing AUR info")?;
    Ok(resp.results.into_iter().next())
}

pub fn pkgbuild(pkg: &str) -> Result<Pkgbuild> {
    info(pkg)?.with_context(|| format!("AUR package not found: {pkg}"))
}

// tiny percent-encode to avoid an extra dep
fn urlencoding_lite(s: &str) -> String {
    s.bytes().map(|b| {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.' | b'~') {
            (b as char).to_string()
        } else {
            format!("%{b:02X}")
        }
    }).collect()
}

#[derive(Deserialize)]
struct RpcResp<T> {
    #[allow(dead_code)]
    version: u8,
    #[allow(dead_code)]
    r#type: String,
    resultcount: u32,
    results: Vec<T>,
}

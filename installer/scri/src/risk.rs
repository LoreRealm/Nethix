//! Risk scanner: heuristic PKGBUILD analysis.

use super::aur::Pkgbuild;

#[derive(Debug, PartialEq, Eq)]
pub enum Severity {
    Info,
    Medium,
    High,
}

#[derive(Debug)]
pub struct Finding {
    pub severity: Severity,
    pub detail: String,
}

#[derive(Debug, Default)]
pub struct RiskReport {
    pub findings: Vec<Finding>,
}

pub fn assess(pb: &Pkgbuild) -> RiskReport {
    let mut r = RiskReport::default();

    // "new" = recently modified is a coarse proxy for low community scrutiny
    let now_unix: i64 = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    if pb.last_modified > now_unix - 14 * 86_400 {
        r.findings.push(Finding { severity: Severity::Info, detail: "recently updated (<14d) — less community scrutiny".into() });
    }

    // suspicious bash patterns (coarse substring scan over declared metadata)
    for pat in SUSPICIOUS {
        if pb.pkgdesc.as_deref().map_or(false, |d| d.contains(pat)) {
            r.findings.push(Finding { severity: Severity::High, detail: format!("suspicious pattern `{pat}` found in pkgdesc") });
        }
    }
    // TODO: fetch actual PKGBUILD text and scan build()/package() bodies
    // TODO: orphan detection needs the search result's maintainer field joined in
    // TODO: check source URLs against known-good host allowlist
    r
}

const SUSPICIOUS: &[&str] = &[
    "curl |", "wget |", "nc -l", "base64 -d", "chmod +s", "/etc/shadow", "/etc/passwd",
];

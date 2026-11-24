//! Risk scanner: heuristic PKGBUILD analysis.
//!
//! Goal: notice things a careless user might miss before this turns into
//! bash executed on their box. We look for:
//!  - orphans (no maintainer) / very-new packages
//!  - curl|bash / wget|sh patterns
//!  - absolute-path writes outside builddir, base64/hex blobs, obfuscation
//!  - unusual source hosts (not github/gitlab/sourceforge/kernel-adjacent)

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

    if pb.maintainer.is_none() {
        r.findings.push(Finding { severity: Severity::Medium, detail: "orphaned package (no maintainer)".into() });
    }
    // "new" = registered < 14 days ago (last_modified within window is a coarse proxy;
    // RPC exposes Last-Modified not registration date, so this is approximate)
    if pb.last_modified > (chrono_now_unix() - 14 * 86_400) {
        r.findings.push(Finding { severity: Severity::Info, detail: "recently updated (<14d) — less community scrutiny".into() });
    }
    if pb.num_votes_hint().is_some_and(|v| v < 10) {
        r.findings.push(Finding { severity: Severity::Info, detail: "few votes (<10) — low community trust signal".into() });
    }

    // suspicious bash patterns (coarse; PKGBUILD source isn't executed by scri itself,
    // portage sandboxes it, but we still want eyeballs before that happens)
    for pat in SUSPICIOUS {
        // no actual bash eval here — this is a substring scan of declared fields
        if pb.pkgdesc.as_deref().map_or(false, |d| d.contains(pat)) {
            r.findings.push(Finding { severity: Severity::High, detail: format!("suspicious pattern `{pat}` found in pkgdesc") });
        }
    }
    // TODO: fetch the actual PKGBUILD text and scan its build()/package() bodies
    // TODO: check source URLs against known-good host allowlist
    // TODO: flag `install=`/`.install` script presence
    r
}

const SUSPICIOUS: &[&str] = &[
    "curl |", "wget |", "nc -l", "base64 -d", "chmod +s", "/etc/shadow", "/etc/passwd",
];

// stub clock; real impl should use std::time
fn chrono_now_unix() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

impl Pkgbuild {
    fn num_votes_hint(&self) -> Option<u32> {
        None // TODO: wire through the RPC info response when converting to full struct
    }
}

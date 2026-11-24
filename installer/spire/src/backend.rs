//! Spire's pluggable package-source backends.
//! Methods are synchronous by design: they run on Task::perform worker
//! threads (never the UI thread), so blocking IO is fine and the trait
//! stays dyn-compatible.

use anyhow::Result;

/// One search result, normalized across backends.
#[derive(Debug, Clone)]
pub struct Listing {
    pub id: String,
    pub name: String,
    pub summary: String,
    pub popularity: u64,
    /// Non-empty for AUR listings with risk signals;
    /// HIGH-severity findings refuse to install from Spire directly.
    pub risk_note: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Aur,
    Flatpak,
}

pub trait Backend: Send + Sync {
    fn name(&self) -> &'static str;
    fn search(&self, q: &str) -> Result<Vec<Listing>>;
    fn install(&self, id: &str) -> Result<()>;
}

pub fn store_backend(kind: Kind) -> &'static dyn Backend {
    match kind {
        Kind::Aur => &ScriBackend,
        Kind::Flatpak => &FlatpakBackend,
    }
}

struct ScriBackend;

impl Backend for ScriBackend {
    fn name(&self) -> &'static str {
        "AUR (via scri)"
    }

    fn search(&self, q: &str) -> Result<Vec<Listing>> {
        let results = scri_lib::aur::search(q)?;
        Ok(results
            .into_iter()
            .map(|r| Listing {
                id: r.name.clone(),
                name: r.name,
                summary: r.description.unwrap_or_default(),
                popularity: r.num_votes as u64,
                risk_note: r.maintainer.is_none().then(|| "orphaned".to_string()),
            })
            .collect())
    }

    fn install(&self, id: &str) -> Result<()> {
        let pb = scri_lib::aur::pkgbuild(id)?;
        let report = scri_lib::risk::assess(&pb);
        if report
            .findings
            .iter()
            .any(|f| f.severity == scri_lib::risk::Severity::High)
        {
            anyhow::bail!(
                "HIGH-severity risk findings — run `scri review {}` and confirm",
                id
            );
        }
        let eb = scri_lib::convert::to_ebuild(&pb)?;
        scri_lib::convert::install_via_portage(&pb, &eb, true)
    }
}

struct FlatpakBackend;

impl Backend for FlatpakBackend {
    fn name(&self) -> &'static str {
        "Flatpak"
    }

    fn search(&self, q: &str) -> Result<Vec<Listing>> {
        let out = run_cmd(&format!(
            "flatpak --columns=application,description search {}",
            shell_escape(q)
        ))?;
        let mut listings = Vec::new();
        for line in out.lines() {
            let mut cols = line.splitn(2, '\t');
            let (Some(app), Some(desc)) = (cols.next(), cols.next()) else {
                continue;
            };
            listings.push(Listing {
                id: app.to_string(),
                name: app.rsplit('/').next().unwrap_or(app).to_string(),
                summary: desc.trim().to_string(),
                popularity: 0,
                risk_note: None,
            });
        }
        Ok(listings)
    }

    fn install(&self, id: &str) -> Result<()> {
        run_cmd(&format!("flatpak install -y flathub {}", shell_escape(id)))?;
        Ok(())
    }
}

fn run_cmd(cmd: &str) -> Result<String> {
    let out = std::process::Command::new("sh")
        .arg("-c")
        .arg(cmd)
        .output()?;
    if !out.status.success() {
        anyhow::bail!(
            "command failed: {}",
            String::from_utf8_lossy(&out.stderr).trim()
        );
    }
    Ok(String::from_utf8_lossy(&out.stdout).to_string())
}

fn shell_escape(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}

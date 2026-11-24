//! scri — AUR helper for Nethix.
//!
//! Scrapes the AUR RPC for any package, converts PKGBUILD -> ephemeral ebuild,
//! lets the user REVIEW (not edit — read-only preview) the generated ebuild
//! plus a risk report, then builds via portage in a scratch overlay.
//!
//! Safety model (per design):
//!  - never redistributes: only the local user fetches AUR metadata/build
//!  - never lets the user hand-edit the generated ebuild (defeats the audit
//!    trail; review is informational, changes happen by adjusting scri config)
//!  - flags: new/unmaintained, votes/ratio, suspicious PKGBUILD patterns
//!
//! CLI: `scri search <q> | scri info <pkg> | scri install <pkg> [--yes]`

mod aur;
mod convert;
mod risk;

use anyhow::{bail, Context, Result};

#[derive(clap::Subcommand, Debug)]
enum Cmd {
    /// search the AUR
    Search { query: String },
    /// fetch and display PKGBUILD + risk report + proposed ebuild
    Review { pkg: String },
    /// review + build + install via portage (requires --yes or TTY confirm)
    Install { pkg: String, #[arg(long)] yes: bool },
}

#[derive(clap::Parser, Debug)]
#[command(name = "scri", about = "AUR bridge for Nethix (read-only review, local build)")]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.cmd {
        Cmd::Search { query } => {
            let results = aur::search(&query)?;
            for r in results {
                println!(
                    "{:<32} {:>6} {:<18} {}",
                    r.name, r.num_votes, r.maintainer.as_deref().unwrap_or("(orphaned)"),
                    r.description.as_deref().unwrap_or("")
                );
            }
        }
        Cmd::Review { pkg } => {
            let pb = aur::pkgbuild(&pkg)?;
            let report = risk::assess(&pb);
            println!("=== risk report: {} ===", pb.pkgname);
            for f in &report.findings {
                println!("[{:?}] {}", f.severity, f.detail);
            }
            if report.findings.iter().any(|f| f.severity == risk::Severity::High) {
                println!("\nHIGH-severity findings present. install will refuse without --yes after second review.");
            }
            println!("\n=== proposed ebuild (read-only preview) ===");
            let eb = convert::to_ebuild(&pb)?;
            println!("{}", eb);
        }
        Cmd::Install { pkg, yes } => {
            let pb = aur::pkgbuild(&pkg)?;
            let report = risk::assess(&pb);
            let high = report.findings.iter().any(|f| f.severity == risk::Severity::High);
            if high && !yes {
                bail!("HIGH-severity risk findings; rerun with --yes to accept, or run `scri review {}` first", pkg);
            }
            let eb = convert::to_ebuild(&pb)?;
            convert::install_via_portage(&pb, &eb, yes)
        }
    }
    Ok(())
}

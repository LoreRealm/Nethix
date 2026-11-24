//! CLI wrapper over the scri library.
//! (search/review/install logic mirrors lib API for terminal use)

use anyhow::{bail, Result};
use clap::Parser;

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
            let results = scri_lib::aur::search(&query)?;
            for r in results {
                println!(
                    "{:<32} {:>6} {:<18} {}",
                    r.name,
                    r.num_votes,
                    r.maintainer.as_deref().unwrap_or("(orphaned)"),
                    r.description.as_deref().unwrap_or("")
                );
            }
        }
        Cmd::Review { pkg } => {
            let pb = scri_lib::aur::pkgbuild(&pkg)?;
            let report = scri_lib::risk::assess(&pb);
            println!("=== risk report: {} ===", pb.pkgname);
            for f in &report.findings {
                println!("[{:?}] {}", f.severity, f.detail);
            }
            if report
                .findings
                .iter()
                .any(|f| f.severity == scri_lib::risk::Severity::High)
            {
                println!("\nHIGH-severity findings present. install will refuse without --yes after second review.");
            }
            println!("\n=== proposed ebuild (read-only preview) ===");
            let eb = scri_lib::convert::to_ebuild(&pb)?;
            println!("{}", eb);
        }
        Cmd::Install { pkg, yes } => {
            let pb = scri_lib::aur::pkgbuild(&pkg)?;
            let report = scri_lib::risk::assess(&pb);
            let high = report
                .findings
                .iter()
                .any(|f| f.severity == scri_lib::risk::Severity::High);
            if high && !yes {
                bail!(
                    "HIGH-severity risk findings; rerun with --yes to accept, or run `scri review {}` first",
                    pkg
                );
            }
            let eb = scri_lib::convert::to_ebuild(&pb)?;
            return scri_lib::convert::install_via_portage(&pb, &eb, yes);
        }
    }
    Ok(())
}

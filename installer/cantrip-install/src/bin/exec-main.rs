//! CLI entry that drives the privileged install from a plan file.
//! Used by scripts/cantrip-install-exec.sh: `cantrip-install --exec PLAN MNT`

use anyhow::{bail, Context, Result};
use nethix_installer_lib::exec::Executor;
use nethix_installer_lib::plan::InstallPlan;

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() >= 2 && args[1] == "--exec" {
        if args.len() < 4 {
            bail!("usage: cantrip-install --exec PLAN MOUNTPOINT");
        }
        let plan_s = std::fs::read_to_string(&args[2]).context("reading plan")?;
        let plan = InstallPlan::from_toml(&plan_s).context("parsing plan")?;
        let mnt = &args[3];
        let ex = Executor { plan };
        ex.prepare_disk(mnt)?;
        ex.unpack_stage3(mnt)?;
        ex.bind_mounts(mnt)?;
        ex.populate(mnt)?;
        ex.cleanup(mnt)?;
        println!("Nethix install complete. Reboot when ready.");
        return Ok(());
    }
    bail!("GUI mode not wired to lib yet; use --exec");
}

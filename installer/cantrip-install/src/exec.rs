//! Privileged back-end: takes an InstallPlan, mutates the target disk,
//! and populates the root via a stage3 chroot + emerge.
//!
//! Design: the GUI never runs as root. It writes a serialized plan
//! (cantrip-install-plan.toml), and a `sudo cantrip-install-exec` step
//! consumes it. This file is the exec-side library.

use crate::plan::{BootMode, FsKind, InstallPlan};
use anyhow::{bail, Context, Result};
use std::process::Command;

pub struct Executor {
    pub plan: InstallPlan,
}

fn sh(cmd: &str, args: &[&str]) -> Result<()> {
    let st = Command::new(cmd)
        .args(args)
        .status()
        .with_context(|| format!("running {cmd} {args:?}"))?;
    if !st.success() {
        bail!("{cmd} {args:?} exited with {st}");
    }
    Ok(())
}

impl Executor {
    /// DESTROY ALL DATA on target_disk. Partition, mkfs, mount.
    pub fn prepare_disk(&self, mnt: &str) -> Result<()> {
        let d = &self.plan.target_disk;
        match self.plan.boot_mode {
            BootMode::Uefi => {
                // GPT: 512MiB ESP + rest root
                sh("sgdisk", &["--zap-all", d])?;
                sh("sgdisk", &["-n1:0:+512M", "-t1:ef00", d])?;
                sh("sgdisk", &["-n2:0:0", "-t2:8300", d])?;
                sh("mkfs.fat", &["-F32", &format!("{d}p1")])?;
                let root = &format!("{d}p2");
                match self.plan.filesystem {
                    FsKind::BtrfsZstd => sh("mkfs.btrfs", &["-L", "nethix-root", root])?,
                    FsKind::Ext4 => sh("mkfs.ext4", &["-L", "nethix-root", root])?,
                }
                sh("mount", &["-o", "compress=zstd:3", root, mnt])?;
                // btrfs subvolumes: @, @home
                if self.plan.filesystem == FsKind::BtrfsZstd {
                    sh("btrfs", &["subvolume", "create", &format!("{mnt}/@")])?;
                    sh("btrfs", &["subvolume", "create", &format!("{mnt}/@home")])?;
                    sh("umount", &[mnt])?;
                    sh("mount", &["-o", "compress=zstd:3,subvol=@", root, mnt])?;
                    std::fs::create_dir_all(format!("{mnt}/home"))?;
                    sh("mount", &["-o", "compress=zstd:3,subvol=@home", root, &format!("{mnt}/home")])?;
                }
                std::fs::create_dir_all(format!("{mnt}/boot/efi"))?;
                sh("mount", &[&format!("{d}p1"), &format!("{mnt}/boot/efi")])?;
            }
            BootMode::Bios => {
                sh("sgdisk", &["--zap-all", d])?;
                sh("sgdisk", &["-n1:0:0", "-t1:8300", d])?;
                let root = &format!("{d}1");
                match self.plan.filesystem {
                    FsKind::BtrfsZstd => sh("mkfs.btrfs", &["-L", "nethix-root", root])?,
                    FsKind::Ext4 => sh("mkfs.ext4", &["-L", "nethix-root", root])?,
                }
                sh("mount", &[root, mnt])?;
            }
        }
        Ok(())
    }

    /// Fetch and unpack the current amd64 stage3 into mnt.
    pub fn unpack_stage3(&self, mnt: &str) -> Result<()> {
        // hardcode a mirror+profile; CI updates this pin periodically
        const STAGE3: "https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-systemd/";
        let _ = STAGE3; // TODO: curl -fL stage3 tarball, verify sha512, untar into mnt with -xattrs
        bail!("unpack_stage3: TODO — download + checksum + tar -xpf");
    }

    /// Bind mounts + resolv.conf so the chroot can use the network.
    pub fn bind_mounts(&self, mnt: &str) -> Result<()> {
        for (src, dst) in [
            ("/proc", "/proc"),
            ("/sys", "/sys"),
            ("/dev", "/dev"),
        ] {
            sh("mount", &["--bind", src, &format!("{mnt}{dst}")])?;
        }
        std::fs::copy("/etc/resolv.conf", format!("{mnt}/etc/resolv.conf"))
            .context("copy resolv.conf")?;
        Ok(())
    }

    /// Run a sequence of chrooted commands: sync tree, install base set,
    /// kernel, bootloader, user setup.
    pub fn populate(&self, mnt: &str) -> Result<()> {
        let step = |c: &str, a: &[&str]| -> Result<()> {
            sh("chroot", &[mnt, c].iter().copied().chain(a.iter().copied()).collect::<Vec<_>>().as_slice())
        };
        step("emerge-webrsync", &[])?;
        // copy in the tuned make.conf picked from microarch_profile
        sh("cp", &[&format!("/var/lib/nethix/makeconf.{}", self.plan.microarch_profile.replace("x86-64-", "amd64-")), &format!("{mnt}/etc/portage/make.conf")])?;
        // copy the overlay in (live ISO already has it; no network needed)
        sh("cp", &["-r", "/var/lib/nethix/overlay", &format!("{mnt}/var/db/repos/nethix")])?;
        step("emerge", &["--oneshot", "sys-apps/portage"])?;
        if self.plan.install_plasma {
            step("emerge", &["--getbinpkg", "kde-plasma/plasma-meta", "media-sound/pipewire", "net-misc/networkmanager"])?;
        }
        step("emerge", &["sys-kernel/nethix-sources"])?;
        // bootloader
        match self.plan.boot_mode {
            BootMode::Uefi => {
                step("emerge", &["sys-boot/efibootmgr", "sys-boot/grub:2"])?;
                step("grub-install", &["--target=x86_64-efi", "--efi-directory=/boot/efi"])?;
            }
            BootMode::Bios => {
                step("emerge", &["sys-boot/grub:2"])?;
                step("grub-install", &[&self.plan.target_disk])?;
            }
        }
        step("grub-mkconfig", &["-o", "/boot/grub/grub.cfg"])?;
        Ok(())
    }

    pub fn cleanup(&self, mnt: &str) -> Result<()> {
        for d in ["/proc", "/sys", "/dev"] {
            let _ = sh("umount", &[&format!("{mnt}{d}")]);
        }
        Ok(())
    }
}

//! Privileged back-end: takes an InstallPlan, mutates the target disk,
//! and populates the root via a stage3 chroot + emerge.
//!
//! Design: the GUI never runs as root. It writes a serialized plan
//! (cantrip-install-plan.toml), and a `sudo cantrip-install-exec` step
//! consumes it. This file is the exec-side library.

use crate::plan::{BootMode, FsKind, InstallPlan};
use anyhow::{bail, Context, Result};
use std::process::Command;

/// Mirror directory listing for current stage3 tarballs.
const STAGE3_BASE: &str =
    "https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-systemd/";

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
        let d = self.plan.target_disk.clone();
        match self.plan.boot_mode {
            BootMode::Uefi => {
                sh("sgdisk", &["--zap-all", &d])?;
                sh("sgdisk", &["-n1:0:+512M", "-t1:ef00", &d])?;
                sh("sgdisk", &["-n2:0:0", "-t2:8300", &d])?;
                sh("mkfs.fat", &["-F32", &format!("{d}p1")])?;
                let root = format!("{d}p2");
                match self.plan.filesystem {
                    FsKind::BtrfsZstd => sh("mkfs.btrfs", &["-L", "nethix-root", &root])?,
                    FsKind::Ext4 => sh("mkfs.ext4", &["-L", "nethix-root", &root])?,
                }
                sh("mount", &["-o", "compress=zstd:3", &root, mnt])?;
                if self.plan.filesystem == FsKind::BtrfsZstd {
                    sh("btrfs", &["subvolume", "create", &format!("{mnt}/@")])?;
                    sh("btrfs", &["subvolume", "create", &format!("{mnt}/@home")])?;
                    sh("umount", &[mnt])?;
                    sh("mount", &["-o", "compress=zstd:3,subvol=@", &root, mnt])?;
                    std::fs::create_dir_all(format!("{mnt}/home"))?;
                    sh("mount", &["-o", "compress=zstd:3,subvol=@home", &root, &format!("{mnt}/home")])?;
                }
                std::fs::create_dir_all(format!("{mnt}/boot/efi"))?;
                sh("mount", &[&format!("{d}p1"), &format!("{mnt}/boot/efi")])?;
            }
            BootMode::Bios => {
                sh("sgdisk", &["--zap-all", &d])?;
                sh("sgdisk", &["-n1:0:0", "-t1:8300", &d])?;
                let root = format!("{d}1");
                match self.plan.filesystem {
                    FsKind::BtrfsZstd => sh("mkfs.btrfs", &["-L", "nethix-root", &root])?,
                    FsKind::Ext4 => sh("mkfs.ext4", &["-L", "nethix-root", &root])?,
                }
                sh("mount", &[&root, mnt])?;
            }
        }
        Ok(())
    }

    /// Download the current systemd stage3, verify its sha512, untar into mnt.
    /// If /var/lib/nethix/stage3.tar.xz already exists (shipped on the ISO),
    /// use that instead of downloading.
    pub fn unpack_stage3(&self, mnt: &str) -> Result<()> {
        let local = std::path::Path::new("/var/lib/nethix/stage3.tar.xz");
        let (tarball, need_cleanup) = if local.exists() {
            (local.to_path_buf(), false)
        } else {
            let index = Command::new("curl")
                .args(["-fsSL", &format!("{STAGE3_BASE}latest-stage3-amd64-systemd.txt")])
                .output()
                .context("fetching stage3 index")?;
            if !index.status.success() {
                bail!("failed to fetch stage3 index");
            }
            let idx = String::from_utf8_lossy(&index.stdout);
            let name = idx
                .lines()
                .find(|l| l.ends_with(".tar.xz"))
                .and_then(|l| l.split_whitespace().last())
                .context("no tarball found in stage3 index")?;
            let url = format!("{STAGE3_BASE}{name}");
            let dest = std::path::PathBuf::from("/tmp/nethix-stage3.tar.xz");
            sh("curl", &["-fLo", dest.to_str().unwrap(), &url])?;
            sh("curl", &["-fLo", "/tmp/stage3.DIGESTS", &format!("{url}.DIGESTS")])?;
            let digests = std::fs::read_to_string("/tmp/stage3.DIGESTS").unwrap_or_default();
            let expect = digests
                .lines()
                .find(|l| l.starts_with("SHA512") && l.contains(name))
                .and_then(|l| l.split_whitespace().nth(1))
                .context("no SHA512 in DIGESTS")?
                .to_string();
            let sum_out = Command::new("sha512sum")
                .arg(&dest)
                .output()
                .context("sha512sum")?;
            let actual = String::from_utf8_lossy(&sum_out.stdout).split_whitespace().next().unwrap_or("").to_string();
            if !expect.eq_ignore_ascii_case(&actual) {
                bail!("stage3 checksum mismatch: expected {expect}, got {actual}");
            }
            (dest, true)
        };

        sh("tar", &["xpf", tarball.to_str().unwrap(), "-C", mnt, "--xattrs-include=*", "--numeric-owner"])?;
        if need_cleanup {
            let _ = std::fs::remove_file("/tmp/stage3.DIGESTS");
        }
        Ok(())
    }

    /// Bind mounts + resolv.conf so the chroot can use the network.
    pub fn bind_mounts(&self, mnt: &str) -> Result<()> {
        for (src, dst) in [("/proc", "/proc"), ("/sys", "/sys"), ("/dev", "/dev")] {
            sh("mount", &["--bind", src, &format!("{mnt}{dst}")])?;
        }
        std::fs::copy("/etc/resolv.conf", format!("{mnt}/etc/resolv.conf"))
            .context("copy resolv.conf")?;
        Ok(())
    }

    /// Chrooted command helper.
    fn chroot_cmd(mnt: &str, cmd: &str, args: &[&str]) -> Result<()> {
        let mut v = vec![mnt, cmd];
        v.extend_from_slice(args);
        sh("chroot", &v)
    }

    /// Create the user account. Password arrives via the root-only
    /// credential file staged by the GUI's pkexec helper; hashed by
    /// chpasswd inside the chroot.
    fn provision_user(&self, mnt: &str) -> Result<()> {
        let cred = std::fs::read_to_string("/var/lib/nethix/user.password")
            .context("reading staged credential (GUI must stage this via pkexec)")?;
        std::fs::write(format!("{mnt}/etc/hostname"), &self.plan.hostname)?;
        Self::chroot_cmd(mnt, "useradd", &[
            "-m", "-G", "wheel,audio,video,plugdev,portage",
            "-s", "/bin/bash", &self.plan.username,
        ])?;
        // set password via stdin pipe to chpasswd
        let mut st = Command::new("chroot")
            .args([mnt, "chpasswd"])
            .stdin(std::process::Stdio::piped())
            .spawn()
            .context("spawning chroot chpasswd")?;
        if let Some(mut si) = st.stdin.take() {
            use std::io::Write;
            si.write_all(format!("{}:{}", self.plan.username, cred.trim()).as_bytes())?;
        }
        let _ = st.wait_with_output()?;
        // shred the staged credential
        let _ = std::fs::remove_file("/var/lib/nethix/user.password");
        Ok(())
    }

    /// Full install sequence: sync, install sets, kernel, bootloader, user.
    pub fn populate(&self, mnt: &str) -> Result<()> {
        Self::chroot_cmd(mnt, "emerge-webrsync", &[])?;
        let mc = format!(
            "/var/lib/nethix/makeconf.{}",
            self.plan.microarch_profile.replace("x86-64-", "amd64-")
        );
        sh("cp", &[&mc, &format!("{mnt}/etc/portage/make.conf")])?;
        sh("cp", &["-r", "/var/lib/nethix/overlay", &format!("{mnt}/var/db/repos/nethix")])?;
        Self::chroot_cmd(mnt, "emerge", &["--oneshot", "sys-apps/portage"])?;
        if self.plan.install_plasma {
            Self::chroot_cmd(mnt, "emerge", &[
                "--getbinpkg", "kde-plasma/plasma-meta",
                "media-sound/pipewire", "net-misc/networkmanager",
            ])?;
        }
        Self::chroot_cmd(mnt, "emerge", &["sys-kernel/nethix-sources"])?;
        match self.plan.boot_mode {
            BootMode::Uefi => {
                Self::chroot_cmd(mnt, "emerge", &["sys-boot/efibootmgr", "sys-boot/grub:2"])?;
                Self::chroot_cmd(mnt, "grub-install", &["--target=x86_64-efi", "--efi-directory=/boot/efi"])?;
            }
            BootMode::Bios => {
                Self::chroot_cmd(mnt, "emerge", &["sys-boot/grub:2"])?;
                Self::chroot_cmd(mnt, "grub-install", &[&self.plan.target_disk])?;
            }
        }
        Self::chroot_cmd(mnt, "grub-mkconfig", &["-o", "/boot/grub/grub.cfg"])?;
        self.provision_user(mnt)?;
        Ok(())
    }

    pub fn cleanup(&self, mnt: &str) -> Result<()> {
        for d in ["/proc", "/sys", "/dev"] {
            let _ = sh("umount", &[&format!("{mnt}{d}")]);
        }
        Ok(())
    }
}

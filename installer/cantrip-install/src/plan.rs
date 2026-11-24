//! Install plan: the serializable contract between the GUI front-end
//! and the privileged back-end that actually mutates disks and runs emerge.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum FsKind {
    BtrfsZstd,
    Ext4,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum BootMode {
    Uefi,
    Bios,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstallPlan {
    /// e.g. "/dev/nvme0n1" — whole-disk install for now
    pub target_disk: String,
    pub filesystem: FsKind,
    pub boot_mode: BootMode,
    /// x86-64-v3 / x86-64-v4 / x86-64-v2
    pub microarch_profile: String,
    pub hostname: String,
    pub username: String,
    pub plaintext_password: Option<String>,
    pub install_plasma: bool,
}

impl Default for InstallPlan {
    fn default() -> Self {
        Self {
            target_disk: String::new(),
            filesystem: FsKind::BtrfsZstd,
            boot_mode: BootMode::Uefi,
            microarch_profile: "x86-64-v3".into(),
            hostname: "nethix".into(),
            username: "user".into(),
            plaintext_password: None,
            install_plasma: true,
        }
    }
}

impl InstallPlan {
    pub fn to_toml(&self) -> anyhow::Result<String> {
        Ok(toml::to_string_pretty(self)?)
    }

    pub fn from_toml(s: &str) -> anyhow::Result<Self> {
        Ok(toml::from_str(s)?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plan_roundtrip() {
        let p = InstallPlan {
            hostname: "victory".into(),
            ..Default::default()
        };
        let s = p.to_toml().unwrap();
        let q = InstallPlan::from_toml(&s).unwrap();
        assert_eq!(p, q);
    }
}

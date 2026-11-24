//! Install plan: serializable contract between GUI front-end and
//! privileged back-end. No credentials are serialized.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum FsKind {
    BtrfsZstd,
    Ext4,
}

impl std::fmt::Display for FsKind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FsKind::BtrfsZstd => write!(f, "btrfs + zstd"),
            FsKind::Ext4 => write!(f, "ext4"),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum BootMode {
    Uefi,
    Bios,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct InstallPlan {
    pub target_disk: String,
    pub filesystem: FsKind,
    pub boot_mode: BootMode,
    /// x86-64-v3 / x86-64-v4 / x86-64-v2
    pub microarch_profile: String,
    pub hostname: String,
    pub username: String,
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
    fn plan_roundtrip_no_credentials() {
        let p = InstallPlan { hostname: "victory".into(), ..Default::default() };
        let s = p.to_toml().unwrap();
        assert!(!s.contains("password"));
        assert!(!s.contains("plaintext"));
        let q = InstallPlan::from_toml(&s).unwrap();
        assert_eq!(p, q);
    }
}

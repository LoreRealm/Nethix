//! Install plan: serializable contract between GUI front-end and
//! privileged back-end. Password is hashed at plan-construction time
//! and NEVER serialized — the exec side receives the hash separately.

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
    pub target_disk: String,
    pub filesystem: FsKind,
    pub boot_mode: BootMode,
    /// x86-64-v3 / x86-64-v4 / x86-64-v2
    pub microarch_profile: String,
    pub hostname: String,
    pub username: String,
    pub install_plasma: bool,
}

/// Password transport: argon2 hash, delivered out-of-band from the TOML plan
/// (written to a root-only file by the GUI process via pkexec/sudo helper).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CredentialBundle {
    pub argon2_hash: String,
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
    fn plan_roundtrip_no_password_leak() {
        let p = InstallPlan { hostname: "victory".into(), ..Default::default() };
        let s = p.to_toml().unwrap();
        assert!(!s.contains("password"));
        assert!(!s.contains("plaintext"));
        let q = InstallPlan::from_toml(&s).unwrap();
        assert_eq!(p, q);
    }
}

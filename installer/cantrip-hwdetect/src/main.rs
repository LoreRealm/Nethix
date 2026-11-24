//! chwd-style hardware detection for Nethix.
//! Scan PCI device IDs, map to kernel modules and VIDEO_CARDS USE flags,
//! write /etc/portage/make.conf adjustments. Placeholder for now.
fn main() -> anyhow::Result<()> {
    for entry in std::fs::read_dir("/sys/bus/pci/devices")? {
        let path = entry?.path();
        let vendor = std::fs::read_to_string(path.join("vendor")).unwrap_or_default();
        let device = std::fs::read_to_string(path.join("device")).unwrap_or_default();
        println!("{}:{}", vendor.trim(), device.trim());
    }
    Ok(())
}

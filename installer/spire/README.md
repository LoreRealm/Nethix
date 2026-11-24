# Spire

App store GUI for Nethix. One interface for:

- **AUR** — powered by the `scri_lib` engine (search, risk assessment,
  PKGBUILD→ebuild, portage-sandboxed install). Listings with HIGH-severity
  findings refuse to install from Spire; the user must run `scri review`
  in a terminal and confirm there.
- **Flatpak** — wraps the `flatpak` CLI (flathub remote).

Backend is a trait (`backend::Backend`) — adding ebuild-repo browsing or
binhost-only mode later means implementing two async methods.

# PvZ2 Gardendless Tauri

Native desktop packaging for **PvZ2 Gardendless** using Tauri.

This repository keeps only the compiled game build in `docs/`, the Tauri wrapper in `src-tauri/`, and GitHub release automation for desktop packages.

## Releases

GitHub Releases are built from version tags such as `v0.8.2`.

Release builds include:

- `PvZ2-Gardendless-macOS-x86_64.dmg`
- `PvZ2-Gardendless-macOS-Apple-Silicon.dmg`
- `PvZ2-Gardendless-macOS-Universal.dmg`
- `PvZ2-Gardendless-Linux-x86_64.deb`
- `PvZ2-Gardendless-Linux-x86_64.AppImage`

Download builds from:

https://github.com/Ic0u/pvge_tauri/releases

macOS builds are unsigned and not notarized. If Gatekeeper blocks the app, approve it from **System Settings > Privacy & Security** or remove quarantine manually after downloading.

## Build Locally

Run the desktop wrapper:

```bash
cargo run --manifest-path src-tauri/Cargo.toml
```

Build a local macOS app and DMG:

```bash
cd src-tauri
cargo tauri build --bundles app,dmg
```

Build a specific macOS target:

```bash
cd src-tauri
cargo tauri build --target x86_64-apple-darwin --bundles dmg
cargo tauri build --target aarch64-apple-darwin --bundles dmg
cargo tauri build --target universal-apple-darwin --bundles dmg
```

## Repository Layout

- `docs/`: compiled PvZ2 Gardendless web assets used by the desktop app.
- `src-tauri/`: Rust/Tauri desktop wrapper.
- `.github/workflows/release.yml`: builds release packages and uploads them to GitHub Releases.

## Credits

PvZ2 Gardendless is created by Gaozih and contributors. This repository packages the compiled build as a Tauri desktop app.

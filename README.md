<div align="center">

<img width="20%" src="src-tauri/icons/source.webp" alt="PvZ2 Gardendless icon">

# PvZ2 Gardendless Tauri Versions

Native desktop builds for people who want to play without pulling a Docker container just to run a game.

Grab the latest build from the [Releases](https://github.com/Ic0u/pvge_tauri/releases) tab.

</div>

## Release Files

Each tagged release builds real desktop packages. For macOS, the release should contain three `.dmg` files:

- `PvZ2-Gardendless-macOS-x86_64.dmg` for Intel Macs.
- `PvZ2-Gardendless-macOS-Apple-Silicon.dmg` for M1/M2/M3/M4 Macs.
- `PvZ2-Gardendless-macOS-Universal.dmg` for both Intel and Apple Silicon.

Linux builds are also included:

- `PvZ2-Gardendless-Linux-x86_64.deb`
- `PvZ2-Gardendless-Linux-x86_64.AppImage`

The release workflow does not publish a website build. It builds desktop release files and uploads them to GitHub Releases.

## Warning: GPU Acceleration

If you want the best GPU acceleration on Linux or macOS, running the Windows version through Proton may still perform better.

Chromium/WebKit WebGL behavior on Linux and macOS can be inconsistent, especially on Wayland. See the upstream tracking issue:

https://github.com/Gzh0821/pvzg_site/issues/85

If you are using the Wine Wayland driver or Crossover, starting the Windows `.exe` with this flag may help:

```bash
--in-process-gpu
```

## Audio Issue

If sound effects do not work, open the in-game settings and set:

```text
Audio Load Mode = DOM
```

## Build Locally

Run the Tauri wrapper:

```bash
cargo run --manifest-path src-tauri/Cargo.toml
```

Build a local macOS DMG:

```bash
cd src-tauri
cargo tauri build --bundles dmg
```

Build specific macOS DMGs:

```bash
cd src-tauri
cargo tauri build --target x86_64-apple-darwin --bundles dmg
cargo tauri build --target aarch64-apple-darwin --bundles dmg
cargo tauri build --target universal-apple-darwin --bundles dmg
```

## Repository Layout

- `docs/`: compiled PvZ2 Gardendless game assets.
- `src-tauri/`: Tauri desktop wrapper.
- `.github/workflows/release.yml`: builds macOS and Linux packages for GitHub Releases.

## Related Projects

- [Android version](https://github.com/Cateners/gardendless-android)
- [PvZ2 Gardendless upstream site](https://github.com/Gzh0821/pvzg_site)

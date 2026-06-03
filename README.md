<div align="center">
<img width="140" src="src-tauri/icons/source.webp" alt="PvZ2 Gardendless icon">

# PvZ2 Gardendless UNo Port

A native desktop wrapper for **PvZ2 Gardendless**, packaged with **Tauri**. For macOS & Linux users who doesnt give a fuck bout docker container, this is unofficial.

[![Release](https://img.shields.io/github/v/release/Ic0u/pvge_tauri?style=flat-square&color=blue)](https://github.com/Ic0u/pvge_tauri/releases)
[![Build](https://img.shields.io/github/actions/workflow/status/Ic0u/pvge_tauri/release.yml?style=flat-square&label=build)](https://github.com/Ic0u/pvge_tauri/actions/workflows/release.yml)
[![License](https://img.shields.io/github/license/Ic0u/pvge_tauri?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey?style=flat-square)]()
[![Tauri](https://img.shields.io/badge/tauri-v2-orange?style=flat-square&logo=tauri&logoColor=white)](https://v2.tauri.app)
[![Rust](https://img.shields.io/badge/rust-stable-brown?style=flat-square&logo=rust&logoColor=white)](https://www.rust-lang.org)

[Releases](https://github.com/Ic0u/pvge_tauri/releases) · [Actions](https://github.com/Ic0u/pvge_tauri/actions/workflows/release.yml) · [Upstream](https://github.com/Gzh0821/pvzg_site)

</div>

---

## Download

Run the installer from Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/Ic0u/pvge_tauri/main/install.sh | bash
```

![demo](demo.gif)

The installer fetches the latest GitHub Release, detects your platform and CPU architecture, downloads the matching build, and installs it automatically.

On macOS, it installs `PvZ2 Gardendless.app` into `/Applications`, removes the quarantine flag, and refreshes the Finder icon cache.

### Manual download

You can also grab the latest build manually from [Releases](https://github.com/Ic0u/pvge_tauri/releases):

| Platform | File |
| --- | --- |
| macOS Intel | `PvZ2-Gardendless-macOS-x86_64.dmg` |
| macOS Apple Silicon | `PvZ2-Gardendless-macOS-Apple-Silicon.dmg` |
| macOS Universal | `PvZ2-Gardendless-macOS-Universal.dmg` |
| Linux x86_64 | `.deb` / `.rpm` / `.AppImage` |
| Linux ARM_64 | `coming soon` |

> [!TIP]
> macOS builds are currently unsigned. If Gatekeeper blocks the app from launching, you can bypass it instantly by opening your Terminal and running:
> ```bash
> xattr -cr "/Applications/PvZ2 Gardendless.app"
> ```

## Updating

The app checks GitHub for new releases on launch and posts a native notification when an update is available. To update, just re-run the one-line installer — it reads your installed version and only reinstalls when something newer exists:

```bash
curl -fsSL https://raw.githubusercontent.com/Ic0u/pvge_tauri/main/install.sh | bash
```

Installer environment overrides:

| Variable | Effect |
| --- | --- |
| `PVZGE_FORCE=1` | Reinstall even if already on the latest version |
| `PVZGE_VERSION=v0.8.2` | Install a specific release instead of latest |
| `PVZGE_ARCH=universal` | Force a macOS variant: `universal`, `x86_64`, or `arm64` |
| `NO_COLOR=1` | Disable colored output |

## Build from Source

**Requirements:** Rust stable, Node.js, [Tauri CLI v2](https://v2.tauri.app), Git

```bash
git clone https://github.com/Ic0u/pvge_tauri.git
cd pvge_tauri
cargo run --manifest-path src-tauri/Cargo.toml
```

## How It Works

The app starts a local asset server on `127.0.0.1` with a random port, then opens a native WebView window pointing to it. Game assets live in `docs/` and are bundled into release builds.

## Troubleshooting

- **No sound** — Set `Audio Load Mode = DOM` in game settings.
- **Missing assets** — Ensure `docs/index.html` exists for local dev.

## License

[GPL-3.0](LICENSE) — Game assets belong to the [upstream project](https://github.com/Gzh0821/pvzg_site).

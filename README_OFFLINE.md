# PvZ2 Gardendless - Desktop Edition (Tauri)

An unofficial desktop port for PvZ2 Gardendless packaging with Tauri, specifically targeting Linux and macOS.

This wrapper provides a native, offline way to play the game on Linux and macOS without needing to set up Docker containers, run local Python web servers, or rely on heavy Electron wrappers.

## Features

- **Native Wrapper**: Built using Tauri v2 and Rust, using the system webview instead of bundling Chromium through Electron.
- **Optimized Asset Packaging**: Keeps Tauri's `frontendDist` tiny and bundles the large `docs/` game build as app resources, avoiding the slow/bloated path of treating ~1.1 GB of assets as the frontend bundle.
- **Offline Asset Delivery**: Starts a local `rouille` server on a random `127.0.0.1` port so multiple app instances can coexist while assets stream from disk.
- **Electron Compatibility**: Loads `docs/tmpPatch.js` before the game code to provide the small `window.electron` API surface the web build expects.
- **Desktop Runtime Fixes**: Applies the canvas/scrollbar sizing patch used by the Electron wrapper and supports `F4`/`F11` fullscreen toggles.

## Development and Building

### Prerequisites

- [Rust toolchain](https://www.rust-lang.org/) installed.

### Run in Debug Mode

```bash
cargo run --manifest-path src-tauri/Cargo.toml
```

### Build Production Package

```bash
cd src-tauri
cargo tauri build
```

Production builds generate native installation formats (`.dmg` / `.app` on macOS, `.deb` on Linux).

For a faster Rust-only verification build:

```bash
cargo build --release --manifest-path src-tauri/Cargo.toml
```

## Platform Settings and Troubleshooting

### GPU Acceleration on Linux / macOS (Alternative Windows Port via Wine)
If running the official Windows build via Wine/Proton/Crossover instead of compiling this native Tauri port:
- Use **Proton** for GPU acceleration on Linux/macOS.
- If using the Wine Wayland driver, start the executable with the `--in-process-gpu` flag to prevent GPU acceleration issues.

Native Tauri builds depend on the platform webview, so WebGL behavior can differ from Chromium/Electron on some Linux and macOS setups.

### Audio Configuration
If sound effects do not play under default engine settings:
1. Open the game settings.
2. Set **Audio Load Mode** to **DOM**.

## Related Links

- [Tauri Configuration](file:///Users/nguyennam/Documents/pvzge_web-master/src-tauri/tauri.conf.json)
- [Gardendless Android Version](https://github.com/Cateners/gardendless-android)

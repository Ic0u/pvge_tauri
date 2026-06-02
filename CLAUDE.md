# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PvZ2 Gardendless — a rewritten "Plants vs Zombies 2" built entirely with web technologies using the Cocos Creator 3.8.4 engine. This repository is a **distribution repo** containing pre-compiled game artifacts (not source code). The game source is built in Cocos Creator externally; this repo hosts the compiled output for web deployment.

Live at: https://play.pvzge.com/

## Tauri Desktop App (macOS Intel wrapper)

The `src-tauri/` directory wraps the game in a native macOS desktop app via Tauri v2. Because the game is 1.1 GB, assets are NOT embedded in the binary — instead, a local HTTP server (`rouille` on port 14567) serves `docs/` from disk at runtime.

```bash
# Development (debug build + launch)
cargo run --manifest-path src-tauri/Cargo.toml

# Production build (.app + .dmg)
cargo tauri build

# The .app bundle lands in src-tauri/target/release/bundle/macos/
# The .dmg lands in src-tauri/target/release/bundle/dmg/
```

Key files:
- `src-tauri/src/lib.rs` — Starts the local asset server, then navigates the webview to `http://127.0.0.1:14567`
- `src-tauri/tauri.conf.json` — Window size 1024×640 (matches game design resolution), bundles `docs/` as external resources
- `dist/index.html` — Minimal placeholder (embedded in binary); immediately replaced by the game via `window.navigate()`

### Why not embed assets?
Tauri's `frontendDist` compiles all files into the binary via `include_dir!`. At 1.1 GB this exceeds LLVM's object size limits. The workaround is `bundle.resources` (copies `docs/` into the .app bundle's `Contents/Resources/`) + a runtime HTTP server.

## Running in Browser (no Tauri)

```bash
# Docker
docker build -t pvzge . && docker run -p 8080:80 pvzge

# Quick alternative — any static file server on the docs/ directory
python3 -m http.server 8080 --directory docs
```

## Repository Structure

- `docs/` — The entire compiled game (~1.1 GB, ~7,200 files). Served as static files.
  - `docs/index.html` — Entry point, loads Cocos engine via SystemJS
  - `docs/application.js` — Game bootstrap (Application class, initializes Cocos and runs `cc.game.run()`)
  - `docs/tmpPatch.js` — Electron API polyfills (fullscreen, shell.openExternal, IPC simulation) for desktop wrapper compatibility
  - `docs/cocos-js/` — Cocos Creator 3.8.4 engine bundle + Ammo physics (WASM + ASM.js fallback)
  - `docs/src/settings.json` — Engine config: design resolution 1024×640, web-mobile platform, Ammo physics, custom rendering layers (LAWN, CHARACTERS, UI_UPPER, etc.)
  - `docs/assets/main/` — Main game scenes and compiled scripts
  - `docs/assets/resources/` — Game assets (sprites, configs)
- `Dockerfile` — nginx:alpine serving `docs/` on port 80
- `.github/workflows/deploy-pages.yml` — CI/CD: deploys the committed `docs/` static build to GitHub Pages

## CI/CD

GitHub Actions deploys `docs/` to GitHub Pages on pushes to `main` and can also be run manually with `workflow_dispatch`. No test suite exists for the compiled web artifact; validate by serving `docs/` locally.

## Key Architecture Details

- **No frontend build pipeline** — the game is compiled in Cocos Creator externally and the output is committed to `docs/`. The only build step is the Tauri/Rust compilation in `src-tauri/`.
- **Module loading** — SystemJS loads modules via `import-map.json`, which maps `cc` to the Cocos engine bundle.
- **Game boot sequence** — `index.html` → SystemJS → `index.js` → `Application` class → loads `settings.json` → `cc.game.run()` → launches `preSplashScene`.
- **Electron compatibility** — `tmpPatch.js` stubs out `electron.ipcRenderer`, `electron.shell`, and fullscreen APIs so the same bundle works in both browser and Electron/Tauri wrappers.
- **Asset breakdown** — ~3,900 MP3 audio files, ~2,700 JSON configs, ~550 PNG sprites, plus WASM binaries for physics.

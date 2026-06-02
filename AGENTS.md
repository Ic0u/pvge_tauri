# Repository Guidelines

## Project Structure & Module Organization

This repository distributes the compiled web build of PvZ2 Gardendless and a Tauri desktop wrapper.

- `docs/` contains the committed Cocos Creator web build served in production and Docker. Treat most files here as generated assets.
- `dist/index.html` is the minimal Tauri `frontendDist` placeholder.
- `src-tauri/` contains the Rust/Tauri desktop app. Runtime logic lives in `src-tauri/src/lib.rs`; the binary entry point is `src-tauri/src/main.rs`.
- `src-tauri/tauri.conf.json` defines the desktop window, bundle targets, icons, and copies `../docs` into app resources.
- `.github/workflows/deploy-pages.yml` deploys the committed `docs/` static build to GitHub Pages.
- Do not commit `src-tauri/target/` build output.

## Build, Test, and Development Commands

- `python3 -m http.server 8080 --directory docs` serves the web build locally at `http://localhost:8080`.
- `docker build -t pvzge .` builds the nginx image that serves `docs/`.
- `docker run -p 8080:80 pvzge` runs the Docker image locally.
- `cargo run --manifest-path src-tauri/Cargo.toml` launches the Tauri desktop wrapper in debug mode.
- `cd src-tauri && cargo tauri build` builds the macOS `.app` and `.dmg` bundles.
- `cargo test --manifest-path src-tauri/Cargo.toml` runs Rust tests when present.

## Coding Style & Naming Conventions

Use Rust 2021 defaults in `src-tauri`: 4-space indentation, `snake_case` functions, `CamelCase` types, and constants in `SCREAMING_SNAKE_CASE`. Run `cargo fmt --manifest-path src-tauri/Cargo.toml` before submitting Rust changes. Keep edits to compiled JavaScript, JSON, WASM, and media assets minimal and explain their source.

## Testing Guidelines

There is no dedicated frontend test suite in this distribution repo. For Rust changes, run `cargo test --manifest-path src-tauri/Cargo.toml`; for lint-sensitive changes, also run `cargo clippy --manifest-path src-tauri/Cargo.toml -- -D warnings`. Smoke-test browser changes by serving `docs/` locally and checking the game loads. Smoke-test desktop changes by confirming the app starts, serves assets on `127.0.0.1:14567`, and opens the game window.

## Commit & Pull Request Guidelines

Visible project history is sparse, with messages like `feat: ...`; prefer concise Conventional Commit-style subjects such as `feat: add macOS bundle resource` or `fix: handle missing docs directory`. Pull requests should include a summary, commands run, affected platforms, screenshots or recordings for UI/game changes, and linked issues. Note any generated asset refreshes and their upstream source.

## Security & Configuration Tips

The Tauri app serves local assets through `rouille` on `127.0.0.1:14567`; avoid exposing this server externally. `tauri.conf.json` currently has `csp: null`, so review security impact before adding remote content, external scripts, or broader Tauri permissions.

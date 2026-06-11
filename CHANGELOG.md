# Changelog

All notable changes to this project will be documented in this file.

## [0.9.3] - 2026-06-11

Game version: `PvZ2_Prerelease_AF_P2`

### Added
- Plant-Decoding Minigame.
- Aerial Fortress Part 2, with levels by @莱池_余垛.
- Bulbkekengi, Loquanado, Pea Commando, Wasabi Whip, and Goo Peashooter.
- Drone Engineer, Arbiter - Model X, and more holiday zombies.
- Recommended and Challenging Card Decks for Aerial Fortress levels.
- Native desktop release packages for macOS Intel, Apple Silicon, Universal, Linux x86_64, and Linux ARM64.

## [0.8.2 build#2] - 2026-06-02

### Fixed
- **Game Save Loss (Critical):** Configured local HTTP server to bind to a preferred fixed port (`21073`) instead of generating a random port each launch. This keeps the WebView's origin stable and permanently preserves game save data stored in `localStorage` across restarts.
- **WebView Security (CSP):** Upgraded from empty/disabled CSP to a secure loopback-only Content Security Policy (`default-src 'self' http://127.0.0.1:* http://localhost:*`).

### Changed
- **Server Performance:** Upgraded local asset server from single-threaded to a multi-threaded pool (4 concurrent workers via `Arc<Server>`) to prevent heavy Cocos Creator asset loading from blocking the main thread.
- **HTTP Caching:** Implemented strategic cache headers in local asset responses (`Cache-Control: public, max-age=31536000, immutable` for static files, and `no-cache` for HTML/JSON). This avoids unnecessary disk I/O reads and guarantees ultra-fast game loading.
- **Clean Code Quality:** Resolved all Rust compiler clippy warnings to satisfy standard Rust code guidelines.

# Rules

Every change to `src-tauri/` must follow these rules. No exceptions.

## Dependencies

Do not add a crate unless you can answer **yes** to all three:
1. Can std alone do this? If yes, use std.
2. Does it justify its weight? Check `cargo bloat --crates` before and after.
3. Is `default-features = false` set with only needed features enabled?

Every dep in `Cargo.toml` must have a one-line comment explaining why it exists.
If a change adds **>500 KB** to the release binary, add a `// SIZE: +Nkb — reason` comment at the usage site.

## File Boundaries

| File | Owns | Does NOT touch |
|------|------|----------------|
| `main.rs` | Entry point, module wiring, Tauri builder | Business logic, HTTP, UI |
| `server.rs` | HTTP server lifecycle, port binding, file serving, docs dir resolution | Window, Tauri API |
| `window.rs` | Window creation, navigation, toast/UI injection, first-launch state | HTTP, server details |
| `error.rs` | Error enum, Display, From impls | Everything else |

A function that doesn't fit one file does not get split across two — refactor until it does.

## Error Handling

- **Zero `unwrap()` / `expect()` in library code.** `main()` may use `unwrap_or_else` + `process::exit` for top-level bailout only.
- **Zero `panic!` in release paths.** The release profile sets `panic = "abort"` — a panic kills the process with no cleanup.
- Every fallible operation returns `Result<T, error::Error>`. Add a variant to `Error` if needed.
- Silence a fallible call with `let _ =` only when failure is truly ignorable (e.g. deleting a temp file).

## Adding a Tauri Command

1. Define the `#[tauri::command]` function in the appropriate module.
2. Return `Result<T, String>` or a serializable error — never panic.
3. Register it in `main.rs` via `.invoke_handler(tauri::generate_handler![...])`.
4. Add required permissions to `capabilities/default.json`.
5. Verify: `cargo clippy`, `cargo build --release`, test on macOS + Linux.

## Clippy

Run `cargo clippy -- -W clippy::all -W clippy::pedantic -A clippy::module_name_repetitions`.
These are **errors**, not warnings. Fix before merge.

## Testing Changes

Before merging, verify the release binary on all supported targets:
```
cargo build --release --target x86_64-apple-darwin
cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-unknown-linux-gnu   # CI or cross
cargo build --release --target aarch64-unknown-linux-gnu   # CI or cross
```
If you cannot cross-compile locally, CI must cover it. No "works on my machine" merges.

## Binary Size Budget

After every PR, run: `ls -lh target/release/pvzge`
If the release binary grew **>500 KB**, the PR description must explain why and whether it can be reduced.

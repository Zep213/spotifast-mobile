# Phase 1: Minimal Android Build + Core Risk Spikes - Pattern Map

**Mapped:** 2026-10-14
**Files analyzed:** 5 (1 new module dir, 4 modified)
**Analogs found:** 5 / 5 (all role-match or exact; no in-repo exact analog exists for the brand-new `AndroidManifest.xml`/`android_main` entry, so that one leans on RESEARCH.md's verified upstream example as a secondary source)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `src/android/mod.rs` (NEW) | platform-entry-module (provider-like) | event-driven (lifecycle callback from `android-activity`) | `src/api/mod.rs` (dir-module shape) + `src/window.rs`/`src/mac_notch.rs` (per-platform `cfg` gating) + RESEARCH.md's `hello_android` example (entry-point body) | role-match (module shape), exact (entry-point body, external source) |
| `src/lib.rs` (MODIFIED — add `pub mod android;`) | module registry | N/A (declarative) | `src/lib.rs` itself, existing `#[cfg(target_os = "macos")]`/`#[cfg(target_os = "linux")]` mod lines | exact |
| `Cargo.toml` (MODIFIED — `[lib]` crate-type, `[target.'cfg(target_os = "android")'.dependencies]`, `[package.metadata.android*]`) | config | N/A | `Cargo.toml`'s existing `[target.'cfg(windows)'.dependencies]` / `[target.'cfg(target_os = "macos")'.dependencies]` / `[target.'cfg(target_os = "linux")'.dependencies]` blocks | exact |
| `build.rs` (MODIFIED — optional Android NDK-link logic, if needed) | config/build-script | N/A | `build.rs`'s existing `#[cfg(windows)]`-gated vcpkg/GLEW logic | exact |
| `src/backend.rs` (MODIFIED — gate 2 `rfd` call sites) | service (command bus / backend handle) | request-response (fire-and-await future via `Command` enum) | `src/backend.rs` itself — nearby `#[cfg(test)]`-gated branches in `api()` (same file, same gating idiom, different predicate) | exact (same file, same idiom, different `cfg` predicate) |
| `AndroidManifest.xml` | config | N/A | None in-repo (cargo-apk synthesizes this from `[package.metadata.android]`; no hand-written manifest exists today) | no analog — see "No Analog Found" |

## Pattern Assignments

### `src/android/mod.rs` (NEW — platform-entry-module, event-driven)

**Analog 1 (module shape — directory-based submodule with a `mod.rs`):** `src/api/mod.rs`

**Pattern** (`src/api/mod.rs` lines 1-7):
```rust
//! Spotify Web API client.

use std::fmt;

pub mod client;
pub mod gateway;
pub mod models;
```
Copy this shape: a top-of-file doc comment describing the module's purpose, then `pub mod` declarations for any sub-files the android module grows (e.g. a later `src/android/audio_spike.rs` for the cpal/AAudio tone test, kept separate from `mod.rs`'s `android_main`).

**Analog 2 (per-platform `cfg` gating idiom, within a single file):** `src/window.rs` lines 66-67, 94, 113, 143

```rust
#[cfg(windows)]
pub fn report_missing_opengl(locale: crate::i18n::Locale) { ... }
```
```rust
pub fn minimize_window(ctx: &egui::Context) {
    #[cfg(target_os = "macos")]
    { /* macOS-specific body */ }
    #[cfg(not(target_os = "macos"))]
    ctx.send_viewport_cmd(egui::ViewportCommand::Minimized(true));
}
```
```rust
#[cfg(target_os = "linux")]
pub fn skip_x11_taskbar(window: raw_window_handle::RawWindowHandle) { ... }
```
Use the same idiom for `android_main`'s outer gate: the whole function is `#[cfg(target_os = "android")]`, matching how `report_missing_opengl`/`skip_x11_taskbar` gate an entire platform-only function rather than scattering `cfg` inside a shared one. Because Android has no analogous shared function to retrofit (it's a brand-new entry point, not an existing cross-platform function growing a new arm), the whole-function gate pattern (`#[cfg(windows)] pub fn ...`) is the right one to copy, not the inline-branch pattern.

**Analog 3 (the actual `android_main` body — no in-repo equivalent exists; sourced from RESEARCH.md, itself fetched directly from `emilk/egui`'s canonical `examples/hello_android/src/lib.rs`, verified against spotifast's exact pinned fork commit and `edition = "2024"`):**

```rust
// src/android/mod.rs
#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
fn android_main(app: winit::platform::android::activity::AndroidApp) {
    android_logger::init_once(
        android_logger::Config::default().with_max_level(log::LevelFilter::Info),
    );

    let options = eframe::NativeOptions {
        android_app: Some(app),
        ..Default::default()
    };
    eframe::run_native(
        "Spotifast",
        options,
        Box::new(|cc| Ok(Box::new(/* minimal Phase 1 app */))),
    )
    .unwrap();
}
```
Note `#[unsafe(no_mangle)]` (not bare `#[no_mangle]`) — required because `Cargo.toml` line 5 already sets `edition = "2024"`, matching upstream's own example exactly; no edition mismatch to resolve.

**Core `eframe::run_native` call-site pattern to mirror (desktop analog, for the `NativeOptions`/app-creator closure shape):** `src/entrypoint.rs` lines 611-663 — the desktop `run()` function's own `eframe::run_native("Spotifast", options, Box::new(move |cc| { ... }))` call. Do **not** modify this function; `android_main` is a separate, parallel entry point (per CONTEXT.md's explicit instruction that desktop's `entrypoint.rs` stays untouched). Copy only the shape (string title `"Spotifast"`, `NativeOptions` struct literal, boxed app-creator closure returning `Ok(Box::new(app))`), not the desktop-specific body (mac_menu/notch init, window-level checks, taskbar hiding — none of that applies on Android in Phase 1's minimal scope).

**Error handling pattern:** `android_main` has no caller to propagate a `Result` to (it's an FFI entry point invoked by `android-activity`), so the upstream/RESEARCH.md pattern's `.unwrap()` on `eframe::run_native(...)` is correct to copy as-is — this differs from `entrypoint.rs::run()`, which returns `eframe::Result<()>` to `main()` (see `src/spotifast.rs` lines 7-9: `fn main() -> eframe::Result<()> { entrypoint::run() }`). Do not try to thread a `Result` back from `android_main`; follow the unwrap-at-the-FFI-boundary idiom instead.

---

### `src/lib.rs` (MODIFIED — add `pub mod android;`)

**Analog:** `src/lib.rs` itself, lines 6-7, 14-15, 26, 28, 30, 32 (existing per-platform module gates)

```rust
#[cfg(target_os = "linux")]
pub mod appearance;
...
#[cfg(any(test, feature = "demo"))]
pub mod demo;
...
#[cfg(target_os = "macos")]
pub mod mac_links;
#[cfg(target_os = "macos")]
pub mod mac_menu;
#[cfg(target_os = "macos")]
pub mod mac_notch;
#[cfg(target_os = "macos")]
pub mod mac_touchbar_crash_guard;
```

**Exact change to make** (insert alphabetically, matching the file's existing alpha-sorted `pub mod` list, right after `account_cache`/`api`/`app`/`appearance` and before `auth`, or wherever alpha order lands it — the file is otherwise strictly alphabetical):
```rust
#[cfg(target_os = "android")]
pub mod android;
```
This is the exact same idiom as the four `mac_*` lines and the one `appearance` line — a single-line `#[cfg(target_os = "...")]` immediately above `pub mod <name>;`, no blank line between them, no doc comment on the declaration itself (the doc comment lives inside the target module file, per `src/api/mod.rs`'s and `src/window.rs`'s own convention).

---

### `Cargo.toml` (MODIFIED)

**Analog:** the three existing `[target.'cfg(...)'.dependencies]` blocks, lines 182-213

```toml
[target.'cfg(target_os = "macos")'.dependencies]
apple-native-keyring-store = { version = "1.0.2", features = ["keychain"] }
# The application menus and Dock menu (src/mac_menu.rs). ...
objc2 = { version = "0.6", features = ["exception"] }
...

[target.'cfg(windows)'.dependencies]
windows-native-keyring-store = { version = "1.1", default-features = false }
# Message loops, the taskbar thumbnail buttons and window styles.
windows-sys = { version = "0.60", features = [...] }

[target.'cfg(target_os = "linux")'.dependencies]
# Reuses the zbus/Tokio stack already used for desktop integration.
zbus-secret-service-keyring-store = { version = "1.0.1", features = ["rt-tokio-crypto-rust"] }
librespot-playback = { version = "0.8", default-features = false, features = ["pulseaudio-backend", "rustls-tls-native-roots"] }
...
```

**Pattern to copy for the new Android block** (insert after the `linux` block, alpha-sorted by the `cfg` key the same way the three existing blocks are grouped by OS):
```toml
[target.'cfg(target_os = "android")'.dependencies]
# AndroidApp type for android_main's signature; eframe does not re-export it.
# Picks up the crmne/winit [patch.crates-io] pin automatically.
winit = { version = "0.30" }
# logcat sink: paths::AppDirs::discover() (directories crate) is unreliable
# on Android (upstream issue, no confirmed fix), so Phase 1 logs to logcat
# instead of a file.
android_logger = "0.15"
# eframe with the Android-only NativeActivity glue in place of the desktop
# windowing backends (wayland/x11 do not apply on Android).
eframe = { version = "0.36", default-features = false, features = ["accesskit", "glow", "default_fonts", "persistence", "android-native-activity"] }
```
Every existing block has a one-line "why this dependency, which file uses it" comment above non-obvious entries (see `objc2`/`objc2-foundation`/`x11rb` comments) — follow that same commenting convention per `CLAUDE.md`'s "no new dependency without a comment" rule (this applies most directly to `android_logger`, the one genuinely new crate).

**`[lib]` crate-type change — analog:** lines 13-15 (current) vs. the upstream pattern RESEARCH.md verified directly from `emilk/egui`'s `hello_android/Cargo.toml`:
```toml
# current
[lib]
name = "spotifast"
path = "src/lib.rs"

# target state (cdylib for Android, lib for desktop [[bin]] — [[bin]] at
# lines 17-19 already depends on [lib] as an rlib via `use spotifast::{...}`)
[lib]
name = "spotifast"
path = "src/lib.rs"
crate-type = ["cdylib", "lib"]
```

**`[package.metadata.android*]` blocks — no in-repo analog (new TOML tables); copy directly from RESEARCH.md's verified snippet** (keys independently confirmed against `rust-mobile/cargo-apk`'s `ndk-build/src/manifest.rs` source, not guessed):
```toml
[package.metadata.android]
package = "rocks.spotifast.spotifast"
build_targets = ["aarch64-linux-android"]

[package.metadata.android.sdk]
min_sdk_version = 26
target_sdk_version = 34

[package.metadata.android.application]
debuggable = true
```

---

### `build.rs` (MODIFIED, only if an Android-specific build-script need surfaces — e.g. NDK link flags; RESEARCH.md's Standard Stack does not currently require one beyond Cargo.toml metadata, so treat this as conditional)

**Analog:** the existing `#[cfg(windows)]`-gated sections, lines 5-6, 9-10, 25-26, 45-91

```rust
#[cfg(windows)]
const GLEW_NAMES: &[&str] = &["glew32s", "libglew32", "glew32"];

#[cfg(windows)]
fn vcpkg_triplet() -> Option<String> { ... }

fn main() {
    fastframe_i18n::build::compile_catalogs("assets/i18n");
    #[cfg(windows)]
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows") {
        println!("cargo:rerun-if-changed=packaging/windows/spotifast.ico");
        let mut resource = winresource::WindowsResource::new();
        ...
        if let Err(error) = resource.compile() {
            println!("cargo:warning=Windows resources not embedded: {error}");
        }
    }
}
```

**Pattern to copy if Android build-script logic becomes necessary:** gate a new `#[cfg(target_os = "android")]` branch inside the same `main()` function, following the exact same `std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("...")` guard style used for the Windows branch (double-gated: both the `#[cfg(windows)]` attribute on the `if` and a runtime env check — the runtime check matters more for cross-compiles where `cfg(windows)` on the build script's own host might differ from the target, though in this project's case `build.rs` always runs on the host, so the attribute alone may suffice; mirror whichever of the two guards the Windows branch actually needs for the new target). Use `println!("cargo:warning=...")` for any non-fatal diagnostic, matching the existing GLEW-library-not-found warning pattern (lines 83-87), rather than panicking the build script.
**Error handling pattern:** non-fatal diagnostics via `cargo:warning=`, not `panic!`/`std::process::exit` — see lines 56-57 (`if let Err(error) = resource.compile() { println!("cargo:warning=..."); }`) and 83-87 (directory-listing diagnostic on missing library).

---

### `src/backend.rs` (MODIFIED — gate 2 `rfd` call sites)

**Analog:** the file's own existing `#[cfg(test)]`-gated branches inside `api()`, lines 1172-1184 (same file, same gating idiom — conditional-compilation branch inside an existing method — applied to a different predicate)

```rust
pub fn api(&self, request: ApiRequest) {
    #[cfg(test)]
    if matches!(
        request,
        ApiRequest::AlbumQueueTracks { .. }
            | ApiRequest::AddToQueue { .. }
            | ApiRequest::AddManyToQueue { .. }
    ) {
        self.queue_requests.lock().unwrap().push(request.clone());
    }
    #[cfg(test)]
    if matches!(
        request,
        ...
```

**Exact call sites to gate** (identified directly in `src/backend.rs`, verified by `grep -n rfd`):

1. **`Command::ChoosePlaylistCover` variant field** — line 614-619:
```rust
ChoosePlaylistCover {
    id: String,
    request: u64,
    selected:
        std::pin::Pin<Box<dyn std::future::Future<Output = Option<rfd::FileHandle>> + Send>>,
},
```
Gate the whole variant (or its field type, per `cfg_attr`/`cfg` on the variant) with `#[cfg(not(target_os = "android"))]`.

2. **`choose_playlist_cover` method body** — lines 1157-1170:
```rust
/// Construct the native dialog on the UI thread, then await and read it
/// on the runtime. AppKit requires its window lookup on the main thread.
pub fn choose_playlist_cover(&self, id: String, request: u64) {
    if self.offline {
        return;
    }
    let selected = rfd::AsyncFileDialog::new()
        .set_title("Choose playlist cover")
        .add_filter("JPEG or PNG image", &["jpg", "jpeg", "png"])
        .pick_file();
    self.send(Command::ChoosePlaylistCover {
        id,
        request,
        selected: Box::pin(selected),
    });
}
```
Gate the whole method with `#[cfg(not(target_os = "android"))]`, matching the whole-function gating idiom already used elsewhere in the codebase (`src/window.rs`'s `#[cfg(windows)] pub fn report_missing_opengl`, `#[cfg(target_os = "linux")] pub fn skip_x11_taskbar`) rather than branching inside the function body — this method has no meaningful Android-side behavior to fall back to (RESEARCH.md Pitfall 1: `rfd` has zero Android backend; there's no partial implementation to keep).
**Scope discipline (per RESEARCH.md Pattern 2):** gate exactly these two sites, nothing else in `backend.rs`. Do not use this as license for a broader desktop-stripping pass — that's Phase 2's job.
**Verification command** (from RESEARCH.md, this exact invocation is how the blocker was originally found and is the fastest way to confirm the gate resolves it):
```bash
cargo apk check --lib --no-default-features -F eframe/android-native-activity --target aarch64-linux-android
```

---

## Shared Patterns

### Per-platform `cfg` gating (whole-item vs. inline-branch)
**Source:** `src/window.rs` (whole-function: lines 66-67, 143), `src/entrypoint.rs` (inline branch inside a shared function: lines 607-610, 634-644, 656-662), `src/backend.rs` (inline branch inside a shared method: lines 1172-1184), `src/lib.rs` (whole-module: lines 6-7, 26, 28, 30, 32)
**Apply to:** every file in this phase's scope — `src/lib.rs`'s `pub mod android;`, `src/backend.rs`'s two `rfd` sites (whole-method/whole-variant gating, since there is no Android-side behavior to keep), `src/android/mod.rs`'s `android_main` (whole-function gating).
**Rule of thumb this codebase follows:** gate the whole item (function, module declaration, struct field, enum variant) when the other platforms don't need a parallel body; gate an inline branch inside a shared function only when the surrounding logic (e.g. `eframe::run_native`'s single call site, `api()`'s single dispatch) must stay one function across all platforms. The `rfd` call sites and `android_main` both fall into the "gate the whole item" case.

### Target-scoped dependency tables in `Cargo.toml`
**Source:** `Cargo.toml` lines 182-213 (`[target.'cfg(target_os = "macos")'.dependencies]`, `[target.'cfg(windows)'.dependencies]`, `[target.'cfg(target_os = "linux")'.dependencies]`)
**Apply to:** the new `[target.'cfg(target_os = "android")'.dependencies]` block (winit, android_logger, Android-feature-flagged eframe) and, if build-script Android logic is added, `[target.'cfg(target_os = "android")'.build-dependencies]` mirroring `[target.'cfg(windows)'.build-dependencies]` (line 227-228, `winresource = "0.1"`).
**Convention:** every non-obvious dependency gets a one-line `#`-comment immediately above it, explaining which source file uses it and why (see `objc2-foundation`'s comment citing `src/mac_links.rs`/`src/window.rs`, `x11rb`'s comment citing `src/window.rs`). This satisfies `CLAUDE.md`'s "no new dependency without an explaining comment" rule and should be followed verbatim for `android_logger` (the one genuinely new crate this phase adds).

### Non-fatal build-script diagnostics
**Source:** `build.rs` lines 56-57, 83-87
**Apply to:** any new Android branch added to `build.rs`'s `main()`, if one proves necessary — use `println!("cargo:warning=...")` for recoverable problems, never `panic!`, matching the existing Windows/GLEW diagnostic style.

### FFI entry-point error handling (unwrap-at-the-boundary)
**Source:** RESEARCH.md's verified `hello_android` example (`eframe::run_native(...).unwrap()`), contrasted with `src/spotifast.rs` lines 7-9 (`fn main() -> eframe::Result<()> { entrypoint::run() }`)
**Apply to:** `src/android/mod.rs`'s `android_main` — there is no caller to propagate a `Result` to across the FFI boundary from `android-activity`, so `.unwrap()` (not `?`/`Result` return type) is the correct, upstream-verified idiom here, diverging intentionally from how `src/spotifast.rs`'s `main()` handles the same `eframe::run_native` call on desktop.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `AndroidManifest.xml` | config | N/A | No hand-written Android manifest exists anywhere in this repo today (desktop packaging uses Flatpak/`packaging/` metadata, not an Android manifest). `cargo-apk` synthesizes this file at build time entirely from `[package.metadata.android]` keys in `Cargo.toml` (confirmed via `rust-mobile/cargo-apk`'s `ndk-build/src/manifest.rs` source, cited in RESEARCH.md) — per D-01/D-02, Phase 1 should **not** hand-write this file at all; the planner should treat `Cargo.toml`'s `[package.metadata.android*]` tables (documented above) as the actual artifact to produce, with the synthesized manifest as a build output to inspect (e.g. via `cargo apk build` then unzipping the APK), not a source file to author. |

## Metadata

**Analog search scope:** `src/` (all top-level `.rs` files + `src/api/`, `src/app/`, `src/milkdrop/` subdirectory modules), `Cargo.toml`, `build.rs`, `src/lib.rs`, `src/spotifast.rs`, `src/entrypoint.rs`, `src/backend.rs`, `src/window.rs`, `src/power.rs`, `src/mac_notch.rs`
**Files scanned:** 12 read/grepped directly (`src/lib.rs`, `src/spotifast.rs`, `build.rs`, `src/backend.rs` [2 targeted ranges], `src/entrypoint.rs` [2 targeted ranges], `src/window.rs`, `Cargo.toml` [2 targeted ranges], `src/api/mod.rs`, `src/power.rs`, `src/mac_notch.rs` header); directory listing of `src/` for module-convention discovery
**Pattern extraction date:** 2026-10-14

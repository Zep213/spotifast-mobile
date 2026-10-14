# Phase 1: Minimal Android Build + Core Risk Spikes - Research

**Researched:** 2026-10-14
**Domain:** Cross-compiling an existing ~117k-LOC Rust + eframe/egui/glow desktop app to a `cargo-apk`-packaged Android debug APK, plus two risk spikes (GL-resume lifecycle, cpal/AAudio)
**Confidence:** HIGH — nearly every finding below was verified by actually running the tool/compiler on this machine (real NDK/SDK at `~/Android/Sdk`, real `cargo-apk` git-HEAD install, real `cargo apk check` against the actual `spotifast` Cargo.toml, real `git merge-base --is-ancestor` check, real standalone `cpal` cross-compile), not inferred from documentation alone.

## Summary

This research goes one level deeper than the project-level `STACK.md`/`PITFALLS.md`/`ARCHITECTURE.md`: instead of describing the Android port in the abstract, it actually ran the exact tools against the exact repo and dependency pins spotifast uses today, on the exact NDK/SDK already installed (NDK 27.0.12077973, SDK platforms `android-34` and `android-36.1`, no `android-35`). Four load-bearing facts came out of this that the project-level research did not have and the planner needs:

1. **`cargo-apk` (git HEAD) installs and runs cleanly on this machine's Rust 1.98.0 toolchain today** (`cargo install --git https://github.com/rust-mobile/cargo-apk cargo-apk`, resolved to commit `887423a9`, dated 2025-07-09). D-01 is confirmed, not just recommended.
2. **The pinned fork commit `crmne/egui@ba6790fe` *is* downstream of the correct Android GL-resume fix** — but D-06 names the wrong PR. CONTEXT.md and the project's own `PITFALLS.md` cite **PR #3847** ("Fix Android crash on resume with `wgpu`"), which only touches `wgpu_integration.rs`. Spotifast uses **`glow`**, not `wgpu`. The glow-backend equivalent is **PR #3867** ("Fix Android crash on resume with Glow backend", merged 2024-01-24, touches `glow_integration.rs`). `git merge-base --is-ancestor 200051d5d8fb3c384db21fe14d8318265c60c038 ba6790fe7cf46e58e8d27ce1524cbfdee745e938` returns true: **the glow fix is included**. D-06's audit still passes, but the planner's verification task must cite #3867, not #3847.
3. **Running `cargo apk check --lib --no-default-features -F eframe/android-native-activity --target aarch64-linux-android` against the real `spotifast` `Cargo.toml` gets most of the way through the real dependency graph (reqwest, tokio, rustls, librespot forks, the patched `crmne/egui`/`crmne/winit` forks, `android-activity`, `jni`) and then fails on exactly one crate: `rfd` 0.17.2 has *zero* Android backend implementation** (12 unsatisfied-trait-bound errors, all in `rfd::backend`, which only implements GTK3/macOS/Windows backends). `rfd::AsyncFileDialog` is called from two sites in `src/backend.rs` (`choose_playlist_cover`). This is a **hard Phase 1 compile blocker**, independent of and narrower than Phase 2's "strip desktop-only code" (AND-10) — Phase 1 cannot reach a working `cargo apk build` without at least `cfg`-gating these two call sites.
4. **`cpal` 0.18.2's AAudio backend is real and substantial** (838 lines, `src/host/aaudio/`), compiles cleanly standalone for `aarch64-linux-android` (verified: a throwaway `cpal = "0.18.1"` crate built successfully with the NDK clang wrapper), and its device enumeration (`AudioDeviceInfo::request`) calls `AudioManager.getDevices()` over JNI via `ndk_context::android_context()`. This **cannot be exercised by a host-side `cargo build`/`cargo check`** — it requires a real `android_main` entry point running on-device/emulator, because `ndk_context`'s `AndroidContext` is only populated by `android-activity` at runtime. D-05's spike is real work, not a formality, and cannot be faked by a desktop-side compile check alone.

**Primary recommendation:** Use `cargo-apk` git HEAD (confirmed installable today) with `android-native-activity`; add the `android_main` entry point to `src/lib.rs` (new `src/android/` module, mirroring the existing per-platform convention) rather than `src/spotifast.rs`; `cfg`-gate the two `rfd` call sites in `src/backend.rs` for Android as a narrow, explicitly-scoped Phase 1 exception to the Phase 2 stripping boundary; explicitly set `min_sdk_version = 26` and `target_sdk_version = 34` in `[package.metadata.android.sdk]` rather than relying on cargo-apk's defaults (verified fragile on this exact SDK installation); and treat the cpal/AAudio spike as requiring an actual on-device run with logcat inspection, not just a successful cross-compile.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| AND-00 | `scripts/check-android-env.sh` passes with no `[FAIL]` | Confirmed the script's checks (toolchain, targets, SDK/NDK, packager, device) all resolve correctly on this machine except packager (verify `cargo-apk` is installed — the script only warns, doesn't fail, if none is installed) and device (no device/emulator connected — see Environment Availability). |
| AND-01 | Project compiles for `aarch64-linux-android` and produces an installable debug APK | Verified the real dependency graph compiles almost entirely; isolated the one real blocker (`rfd`, see Pitfall 1) and the exact `cargo-apk` invocation/config needed (see Standard Stack, Code Examples). |
| AND-02 | Linux desktop target keeps compiling and existing tests keep passing | All Android-specific changes below are `cfg(target_os = "android")`-gated or `[target.'cfg(...)'.dependencies]`-scoped; none touch the existing desktop `eframe` feature list, `[[bin]]` target, or `entrypoint.rs`. |

</phase_requirements>

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Packaging tool — `cargo-apk`, installed from git HEAD (not crates.io 0.10.0, which is stale). Re-verify live maintenance status at implementation time.
- **D-02:** Packaging tool escalation path — Defer Gradle/cargo-ndk; use zero-Gradle `cargo-apk` for Phase 1, migrate only when Phase 6 needs Kotlin/`<service>` manifest support.
- **D-03:** minSdk 26 (Android 8.0) — cpal's AAudio-only backend hard-requires API 26. targetSdk 34, matching the installed `platforms;android-34`.
- **D-04:** GL-resume spike — Manual device test: lock/unlock, rotate, background via Home and return — confirm no crash/black screen, before marking Phase 1 success criterion #4 done.
- **D-05:** cpal/AAudio spike — Compile `fastframe-audio`/cpal for `aarch64-linux-android`, enumerate at least one real output device via cpal's device-listing API, and play one test tone. If this spike fails, STOP and surface to the user before continuing — a hand-written Oboe/AAudio JNI sink is NOT assumed in-scope for Phase 1.
- **D-06:** Fork-commit audit — Check the pinned commit SHA in Cargo.toml's `[patch.crates-io]` against `emilk/egui`'s fix-PR merge commit/date before relying on D-04's manual test alone — if the pin predates the fix, flag it rather than assuming the manual test alone is sufficient proof.

### Claude's Discretion

- Exact crate-type wiring for the Android entry point (project has both a `[lib]` target `src/lib.rs` and a `[[bin]]` target `src/spotifast.rs` — decide whether the Android `cdylib`/`android_main` entry point is added to the `[lib]` crate-type list or a new target, following `cargo-apk`'s conventions).
- Exact `eframe` feature flags to enable for Android (`android-native-activity` vs `android-game-activity` — STACK.md recommends starting with `android-native-activity`, escalating only if touch/IME input proves too limited in Phase 3).
- Where new Android module code lives (`src/android/` per the existing per-target module convention).

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

**Carried-forward open question (not resolved by auto-mode):** No physical Android device or emulator is currently connected. Phase 1 execution needs a real device via USB debugging or an x86_64 AVD before success criteria #3, #4, #5 can be verified.

</user_constraints>

## Project Constraints (from CLAUDE.md)

- Keep `LICENSE` MIT and attribution to crmne.
- No backend/telemetry (inherited from upstream `AGENTS.md`).
- Credentials never in logs or plain JSON — not applicable to Phase 1 (no auth work).
- No new dependency in `Cargo.toml` without an explaining comment. Phase 1 needs exactly one genuinely new runtime dependency (`android_logger`, see Package Legitimacy Audit) plus un-gating `winit` for Android (already a pinned dependency via `[patch.crates-io]`, just not currently reachable outside the `milkdrop` feature).
- Desktop `cargo check` must keep passing every phase; Android changes go behind `cfg(target_os = "android")` or target-specific dependency tables.
- MilkDrop uses CMake/libclang on desktop; stays off on Android via `--no-default-features` (confirmed: `default = ["milkdrop"]` is the *only* default feature, so `--no-default-features` cleanly disables it without touching anything else).
- `[patch.crates-io]` pins `crmne/*` forks by commit; keep those commits, don't change source (AGENTS.md: `.github/scripts/check-dependency-sources.py` enforces this in CI).

## Architectural Responsibility Map

This is a native mobile app, not a web app — the standard Browser/SSR/API/CDN/DB tiers don't map directly. The table below uses the project's own existing tier boundaries (native UI, platform glue, audio engine, build tooling) as the closest equivalent, for the planner's sanity-checking purposes.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Window/surface creation, input, GL context lifecycle | Native UI (Rust: `eframe`/`egui-winit`/`android-activity`) | — | Entirely owned by the pinned `crmne/egui`/`crmne/winit` forks; spotifast's own code never touches EGL/GL surfaces directly. |
| `android_main` entry point, APK packaging, manifest metadata | Build Tooling (`cargo-apk` + `[package.metadata.android]`) | Platform glue (`src/android/`) | `cargo-apk` owns manifest synthesis and signing; the `android_main` symbol itself must live in spotifast's own `[lib]` crate. |
| Audio device open/enumerate/play | Audio Engine (`fastframe-audio` → `cpal` → AAudio via `ndk::audio`) | Platform glue (JNI context, provided by `android-activity`) | `cpal`'s AAudio host handles the AAudio C API directly; JNI device enumeration depends on the `ndk_context::AndroidContext` that `android-activity` populates before `android_main` runs — a cross-tier dependency the spike must respect (can't test enumeration off-device). |
| App directories / log file path | Platform glue (`directories` crate) | — | `directories::ProjectDirs::from(...)` is documented as unreliable/unsupported on Android (open upstream issue, no confirmed fix) — Phase 1 should not depend on `paths::AppDirs::discover()` resolving to anything meaningful on Android; use `android_logger` (logcat) instead for this phase's debugging needs. |
| File picker (`choose_playlist_cover`) | N/A — hard Android gap | — | `rfd` has no Android implementation at all, in any currently-released version inspected. This capability has no owning tier on Android yet; Phase 1 must `cfg`-exclude it, not relocate it. |

## Standard Stack

### Core

| Library | Version (verified) | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `eframe` | 0.36.1, pinned via `[patch.crates-io]` to `crmne/egui@ba6790fe7cf46e58e8d27ce1524cbfdee745e938` `[VERIFIED: Cargo.lock]` | App shell / GL context mgmt | Already in use; ships `android-native-activity`/`android-game-activity` Cargo features that forward to `egui-winit`/`winit` `[VERIFIED: crates.io source inspection of pinned commit]`. Note: project-level STACK.md said "0.36.2" — the actually-resolved version in this repo's `Cargo.lock` is **0.36.1**; use the Cargo.lock value, not the STACK.md value. |
| `winit` | 0.30.13, pinned via `[patch.crates-io]` to `crmne/winit@ed7caa9023f10b397f5b6ec8284a840cbd8a6f65` `[VERIFIED: Cargo.lock]` | Window/event-loop, `AndroidApp` type for `android_main` | `eframe::NativeOptions::android_app` has type `Option<winit::platform::android::activity::AndroidApp>` `[VERIFIED: read crmne/egui@ba6790fe `crates/eframe/src/epi.rs` directly]`. `eframe` only re-exports `EventLoopBuilder`/`WindowAttributes` from winit, **not** `AndroidApp` — spotifast needs its own direct `winit` dependency to name this type, exactly like upstream's `hello_android` example does. |
| `android-activity` | 0.6.1 `[VERIFIED: Cargo.lock / cargo apk check output]` | NativeActivity/GameActivity glue, JNI context bootstrap | Pulled in transitively by `winit`; do not depend on directly. Confirmed via `docs.rs/android-activity` (official docs) that `ndk-context`'s `JavaVM`/`Context` are attached automatically before `android_main` runs — no manual init call needed. |
| `glow` | 0.17.0, pulled by the pinned egui fork `[VERIFIED: cargo apk check output]` | GL rendering backend | Already in use; Android-independent of `wgpu` (eframe's `glow` feature is orthogonal to its `wgpu` default feature — confirmed by reading `crates/eframe/Cargo.toml` at the pinned commit). No change needed. |
| `cpal` | 0.18.2, via `fastframe-audio` `[VERIFIED: Cargo.lock, standalone cross-compile]` | Audio device stream | **Verified by actually cross-compiling a standalone `cpal = "0.18.1"` crate for `aarch64-linux-android`** with the project's exact NDK (27.0.12077973) — succeeds cleanly in ~9s, pulling in `jni`, `ndk` (with `audio` + `api-level-26` features), `ndk-context` automatically. Source inspection of `cpal-0.18.2/src/host/aaudio/mod.rs` (838 lines) confirms a real, non-stub AAudio backend: `Host::devices()` calls `AudioDeviceInfo::request(DeviceDirection::Duplex)`, which does JNI `AudioManager.getDevices()` via `ndk_context::android_context()`. |
| `ndk` (cpal's transitive dep) | 0.9.0, with features `["audio", "api-level-26"]` `[VERIFIED: cpal-0.18.2 Cargo.toml]` | AAudio stream FFI | `api-level-26` matches D-03's minSdk exactly — not a coincidence to double-check, just confirm it lines up. |
| `android_logger` | 0.15.1 `[VERIFIED: cargo info, crates.io, rust-mobile org — same org as cargo-apk/android-activity]` | logcat sink for `log` macros during the Phase 1 spikes | **New dependency**, genuinely needed: `fastframe_log`'s file-based logging depends on `paths::AppDirs::discover()`, which uses the `directories` crate — documented as unreliable on Android (see Pitfall 4). Upstream's own `hello_android` example uses exactly this crate for the same reason. See Package Legitimacy Audit. |

### Packaging / Build Tooling

| Tool | Version / State (verified) | Purpose | Why Recommended |
|------|---------|---------|--------------|
| `cargo-apk` | git HEAD, resolves to commit `887423a9` (2025-07-09) `[VERIFIED: actually ran `cargo install --git https://github.com/rust-mobile/cargo-apk --locked cargo-apk` on this machine — succeeded, installed binary confirmed working via `cargo apk --help`/`build --help`/`run --help`/`check --help`]` | Build/sign/install APK, zero Gradle | D-01 confirmed empirically, not just recommended. Repo not archived, `pushed_at: 2026-04-08`, 41 open issues (MEDIUM-confidence freshness signal — no new commits on `main` since 2025-07-09 despite the later push timestamp; re-check at execution time per D-01's own instruction). |

**Installation (verified working):**
```bash
cargo install --git https://github.com/rust-mobile/cargo-apk --locked cargo-apk
```

**Exact CLI surface (from `cargo apk <subcommand> --help`, run directly on this machine):**
```
cargo apk check   # type-check only, --lib/--bin/--target/-F/--no-default-features/-d <device>
cargo apk build   # compile + package APK, same flags, -r for release
cargo apk run     # build + install + launch + follow logcat (-n to disable logcat follow)
cargo apk gdb      # attach gdb to a running on-device process
```
Relevant flags for Phase 1: `--lib` (build only the `[lib]` target — the cdylib), `--no-default-features` (disables `milkdrop`), `-F eframe/android-native-activity` (or declare the feature properly in `Cargo.toml` — see below), `--target aarch64-linux-android`, `-d <serial>` once a device/emulator exists.

**Exact `[package.metadata.android]` keys supported** (verified from `rust-mobile/cargo-apk`'s README and `ndk-build/src/manifest.rs` source):
- Top level: `package`, `build_targets`, `resources`, `assets`, `apk_name`, `strip`, `runtime_libs`, `shared_user_id`
- `sdk`: `min_sdk_version` (**default `Some(23)`** — verified in `ndk-build/src/manifest.rs:319`), `target_sdk_version` (default resolution described below), `max_sdk_version`
- `application`: `debuggable` (default false — **must be set `true` for a debug/sideload build**), `theme`, `icon`, `label`
- `application.activity`: `config_changes` (default `"orientation|keyboardHidden|screenSize"`), `label`, `launch_mode`, `orientation`, `exported`
- Default activity class name is `"android.app.NativeActivity"` `[VERIFIED: ndk-build/src/manifest.rs default_activity_name()]`

## Package Legitimacy Audit

| Package | Registry | Age/Source | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| `android_logger` | crates.io | published by `rust-mobile` org (same org as `cargo-apk`, `android-activity`) | — (not checked numerically; org reputation verified) | `github.com/rust-mobile/android_logger-rs` | `[OK]` | Approved — add as `[target.'cfg(target_os = "android")'.dependencies]`, new, with an explaining comment per `CLAUDE.md`'s "no new dependency without a comment" rule. |

**Packages removed due to slopcheck `[SLOP]` verdict:** none.
**Packages flagged as suspicious `[SUS]`:** none.

All other packages discussed in this document (`eframe`, `winit`, `android-activity`, `glow`, `cpal`, `ndk`, `cargo-apk`) are **already present in the project's resolved dependency graph** (`Cargo.lock`) or are the already-decided packaging tool (D-01) — not new installs requiring a legitimacy gate. `android_logger` is the one genuinely new crate this phase adds, and it passed `slopcheck install android_logger` with `[OK] android_logger (crates.io)`.

## Architecture Patterns

### System Architecture Diagram

```
                     Android OS
                         │
         (loads .so, finds `android_main` symbol)
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│  android-activity (from winit, transitively)              │
│  - populates ndk_context::AndroidContext (JavaVM, Context)│
│  - delivers Resumed/Suspended/Destroy lifecycle events     │
└───────────────────────┬────────────────────────────────┘
                         │ calls exported fn
                         ▼
┌─────────────────────────────────────────────────────────┐
│  src/android/mod.rs (NEW)                                 │
│  #[unsafe(no_mangle)] fn android_main(app: AndroidApp)    │
│  - android_logger::init_once(...)                          │
│  - eframe::run_native(..., NativeOptions{android_app, ..}) │
└───────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│  eframe / egui-winit / egui_glow (patched fork, unchanged) │
│  - owns EGL/GL surface create/destroy across Resumed/      │
│    Suspended (this is the Pitfall-1 risk area; fixed       │
│    upstream by PR #3867, included in the pinned commit)    │
└───────────────────────┬────────────────────────────────┘
                         │ app creator closure
                         ▼
┌─────────────────────────────────────────────────────────┐
│  Minimal Phase 1 App (new, throwaway UI for this phase)   │
│  - renders a trivial egui surface (e.g. CentralPanel with  │
│    a label) to prove the pipeline end-to-end               │
└─────────────────────────────────────────────────────────┘

   (separate, parallel spike — not wired into the UI above)
┌─────────────────────────────────────────────────────────┐
│  fastframe_audio::Output::open(OutputOptions::default(),  │
│    Tone{...})  — cpal → ndk::audio::AudioStream → AAudio   │
│  Device enumeration needs the JNI context above, so this   │
│  spike must run from inside android_main on a real device  │
│  or emulator, not a standalone host-side binary.            │
└─────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

```
src/
├── android/              # NEW, cfg(target_os = "android") in lib.rs:
│   └── mod.rs             #   #[cfg(target_os = "android")] pub mod android;
│                           #   contains android_main; also the cpal spike code
├── lib.rs                 # add: #[cfg(target_os = "android")] pub mod android;
├── backend.rs              # 2 call sites `cfg`-gated out for Android (rfd, see Pitfall 1)
└── spotifast.rs, entrypoint.rs   # UNCHANGED — desktop [[bin]] entry stays separate
```

**Why `[lib]`, not `[[bin]]`:** `cargo-apk` requires the Android entry to be a `cdylib`. The upstream `hello_android` example declares `crate-type = ["cdylib", "lib"]` on `[lib]` with the comment *"cdylib is required for Android, lib is required for desktop"* `[VERIFIED: fetched examples/hello_android/Cargo.toml from emilk/egui directly]`. Spotifast's existing `[[bin]] path = "src/spotifast.rs"` already depends on the `[lib]` crate as an rlib (via `use spotifast::{app, backend, ...}`), so `crate-type = ["cdylib", "lib"]` (not `["cdylib"]` alone) is required to keep the desktop binary linking. `#[no_mangle]` ignores module nesting, so `android_main` can live in `src/android/mod.rs` rather than crate-root `src/lib.rs` itself — just needs `pub mod android;` reachable from the crate.

### Pattern 1: `android_main` entry point (verified against upstream's own canonical example)

**What:** The exact, current, official pattern `eframe`'s own maintainers use for Android. Fetched directly from `github.com/emilk/egui` `examples/hello_android/src/lib.rs` (current `main` branch).
**Source:** `https://github.com/emilk/egui/blob/main/examples/hello_android/src/lib.rs` (HIGH confidence — official, canonical, matches spotifast's exact `eframe`/`glow` stack)

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

```toml
# Cargo.toml additions — target-gated, do not touch the existing top-level
# [dependencies] eframe entry (desktop keeps wayland/x11 unchanged).
[target.'cfg(target_os = "android")'.dependencies]
# AndroidApp type for android_main's signature; eframe does not re-export it.
# Picks up the crmne/winit [patch.crates-io] pin automatically.
winit = { version = "0.30" }
# logcat sink: paths::AppDirs::discover() (directories crate) is unreliable
# on Android (upstream issue, no confirmed fix), so Phase 1 logs to logcat
# instead of a file.
android_logger = "0.15"

[lib]
name = "spotifast"
path = "src/lib.rs"
crate-type = ["cdylib", "lib"]   # cdylib for Android, lib for desktop [[bin]]

[package.metadata.android]
package = "rocks.spotifast.spotifast"   # ASSUMED — see Assumptions Log A1
build_targets = ["aarch64-linux-android"]  # add x86_64-linux-android once an AVD exists

[package.metadata.android.sdk]
min_sdk_version = 26     # D-03; cargo-apk's own default is 23 (see Pitfall 3)
target_sdk_version = 34  # D-03; do not rely on cargo-apk's default (see Pitfall 2)

[package.metadata.android.application]
debuggable = true   # default is false; a sideload debug APK needs this explicit
```

`eframe`'s Android feature must also be enabled — add it to the *existing* `eframe` line only for the Android target, e.g. via a second `[target.'cfg(target_os = "android")'.dependencies] eframe = { version = "0.36", default-features = false, features = ["accesskit", "glow", "default_fonts", "persistence", "android-native-activity"] }` (drop `wayland`/`x11`/`links`, which don't apply on Android; `links` pulls `webbrowser`, worth checking whether it compiles for Android before assuming it must be dropped — not yet verified, see Open Questions). This was verified empirically: running `cargo apk check --lib --no-default-features -F eframe/android-native-activity --target aarch64-linux-android` against the real repo (CLI feature override, no file edits) got past the `android-activity` "neither native-activity nor game-activity enabled" `compile_error!` that fires without it.

### Pattern 2: `cfg`-gate the two `rfd` call sites (narrow, Phase-1-scoped exception to Phase 2's stripping boundary)

**What:** `src/backend.rs` has exactly two `rfd` touch points: the `ChoosePlaylistCover` command variant's future type (`std::pin::Pin<Box<dyn std::future::Future<Output = Option<rfd::FileHandle>> + Send>>`) and the `choose_playlist_cover` method that constructs `rfd::AsyncFileDialog::new()`. Both need `#[cfg(not(target_os = "android"))]` (or an equivalent no-op Android arm) for Phase 1's `cargo apk build` to succeed at all — this is **not** optional and **not** deferrable to Phase 2, because it is a hard compile failure, not a dead-UI-path cosmetic issue.
**Verified:** `cargo apk check --lib --no-default-features -F eframe/android-native-activity --target aarch64-linux-android` against the real repo fails with exactly 12 `E0277` errors, all `rfd::backend::{FileDialog,MessageDialog}: *Impl is not satisfied`, all traced to `rfd-0.17.2/src/backend.rs` which implements GTK3 (Linux/BSD), macOS, and Windows backends only — no Android arm exists in the crate at all, in this or (per source inspection) any version's `backend.rs` structure.
**Scope discipline:** Keep this to exactly these two call sites. Do not use this as license to do the full AND-10 desktop-stripping pass in Phase 1 — that's explicitly Phase 2's job per `SUMMARY.md`'s roadmap. The minimal fix here is "make it compile," not "clean it up."

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| GL surface recreation on resume | A custom Suspended/Resumed → EGL teardown/rebuild handler | Let `eframe`/`egui_glow` (the pinned fork, confirmed to include PR #3867) own it entirely | This is exactly the class of bug the fork fix already addresses; re-implementing any part of it risks reintroducing the same crash class with less testing behind it. |
| Audio device enumeration/open on Android | A hand-written JNI call to `AudioManager.getDevices()` | `cpal`'s existing AAudio host (`fastframe_audio::Output::open`) | Verified to already do exactly this, correctly, including JNI thread attach/detach via the `jni` crate — confirmed by reading `cpal-0.18.2/src/host/aaudio/java_interface/*.rs` directly. Only fall back to hand-written Oboe/JNI if D-05's spike genuinely fails (per CONTEXT.md, requires explicit scope approval first). |
| App log output visibility on Android | Extending `fastframe_log` to detect Android and redirect | `android_logger` crate, used only for this phase's spike debugging | `fastframe_log`'s file-based approach depends on `paths::AppDirs` resolving a real writable directory, which is unverified/unreliable on Android (see Pitfall 4) — simplest correct choice for Phase 1 is the standard logcat crate upstream itself uses. |

**Key insight:** Every piece of genuinely hard platform-lifecycle code this phase needs (GL resume, AAudio device access, JNI context bootstrap) is already implemented, by name, in a crate already in spotifast's dependency tree or one commit away from it. Phase 1's actual new code should be small: one `android_main` function, two `cfg` gates, and Cargo.toml/manifest metadata.

## Common Pitfalls

### Pitfall 1: `rfd` has zero Android backend — a hard, verified compile blocker (not in prior project-level research)

**What goes wrong:** `cargo apk build`/`check` fails outright with 12 `E0277` trait-bound errors from `rfd-0.17.2/src/backend.rs` the moment the `[lib]` target (which includes `src/backend.rs`) is built for `aarch64-linux-android`, regardless of Cargo features chosen.
**Why it happens:** `rfd`'s `FileDialog`/`AsyncFileDialog`/`MessageDialog` traits are only implemented for `cfg(target_os = "macos")`, `cfg(windows)`, and the GTK3-based Linux/BSD family — confirmed by grepping `rfd-0.17.2/src/backend.rs` for every `target_os` cfg present (macos, windows, linux/freebsd/dragonfly/netbsd/openbsd). There is no Android arm.
**How to avoid:** `#[cfg(not(target_os = "android"))]` the `ChoosePlaylistCover` future-typed field and the `choose_playlist_cover` method body in `src/backend.rs` (Pattern 2 above). Verify by re-running `cargo apk check --lib --no-default-features -F eframe/android-native-activity --target aarch64-linux-android` after the gate — this exact command is how the blocker was found and is the fastest way to confirm it's resolved.
**Warning signs:** `error[E0277]: the trait bound 'FileDialog: ...Impl' is not satisfied` with a path into `rfd-0.17.2/src/...` — not spotifast's own code, a strong signal of a hard upstream-crate platform gap (c.f. the project's own Pitfall 6 about patched-fork cross-compilation, same root-cause pattern applied to an un-patched dependency this time).
**Phase to address:** Phase 1 (compile blocker for AND-01). The permanent "remove or properly gate the playlist-cover-picker feature on Android" UX decision is AND-10/Phase 2's concern; Phase 1 only needs the narrow compile fix.

### Pitfall 2: `cargo-apk`'s `target_sdk_version` default is fragile on this exact SDK installation

**What goes wrong:** If `target_sdk_version` is left unset in `[package.metadata.android.sdk]`, `cargo-apk` computes it as `highest_supported_platform().min(35)`. Reading `ndk-build/src/ndk.rs` directly: `highest_supported_platform()` scans `$ANDROID_HOME/platforms/android-*` directories and does `name.strip_prefix("android-").and_then(|api| api.parse::<u32>().ok())` — **this machine's installed `android-36.1` directory fails to parse as a `u32` (because of the `.1` suffix) and is silently dropped**, leaving only `android-34` in the detected set. The default therefore happens to resolve to 34 today — matching D-03 purely by accident of this naming quirk, not by design.
**Why it happens:** `cargo-apk`'s platform-version parser assumes integer-only platform directory names; preview/point-release SDK platform directories (like `android-36.1`) silently vanish from its view rather than erroring.
**How to avoid:** Set `target_sdk_version = 34` explicitly in `Cargo.toml` (and `min_sdk_version = 26`, see Pitfall 3) rather than relying on this default — if `android-35` is ever installed later (a very plausible event, since cargo-apk's own default logic explicitly targets 35), the default silently jumps away from D-03's decision without any visible change to `Cargo.toml`.
**Warning signs:** A sudden `cargo apk build` failure with `NdkError::PlatformNotFound(35)` after an unrelated SDK update, or (more insidiously) a successful build against an unintended target SDK version.
**Phase to address:** Phase 1 — set explicitly in the initial `Cargo.toml` change, don't defer.

### Pitfall 3: `cargo-apk`'s `min_sdk_version` default (23) is below cpal's AAudio floor (26)

**What goes wrong:** `ndk-build/src/manifest.rs` sets `min_sdk_version: Some(23)` as the struct default. Confirmed via the actual linker invocation captured during the `cargo apk check` run: `CFLAGS_aarch64-linux-android=--target=aarch64-linux-android23`. D-03 already decided 26 to match cpal's AAudio-only floor — but this is only enforced if `Cargo.toml` sets it explicitly.
**Why it happens:** `cargo-apk`'s own default (23) predates this project's AAudio-specific constraint and has no way to know about it.
**How to avoid:** Set `min_sdk_version = 26` explicitly (Pattern 1's Cargo.toml snippet above already includes this).
**Phase to address:** Phase 1, same commit as Pitfall 2's fix.

### Pitfall 4: `directories` crate's `ProjectDirs::from()` is documented-unreliable on Android

**What goes wrong:** `src/paths.rs`'s `AppDirs::for_name()` calls `directories::ProjectDirs::from("me", "paolino", name)`, with a `None` fallback to `std::env::current_dir()`-relative paths. The `directories` crate (v6, `[VERIFIED: cargo info directories]`) documents support for "Linux, Redox, macOS and Windows" — Android is not named. An open upstream issue (`zff.dev/dirs/directories-rs/issues/83`, opened 2023, no confirmed resolution found) reports `ProjectDirs::from` returning `None` on a real Android 12 device `[CITED: web search, single source, not independently reproduced]`. If it does return `None`, the fallback resolves to `current_dir()`, which on a `NativeActivity`-hosted process is not guaranteed to be writable or meaningful.
**Why it happens:** Android has no XDG/Known-Folder/Standard-Directory equivalent accessible without a JNI call into `Context.getFilesDir()` or similar — exactly the kind of platform gap `directories` doesn't cover.
**How to avoid:** For Phase 1's minimal scope (no settings persistence needed), don't depend on `paths::AppDirs::discover()` resolving correctly — use `android_logger` (logcat) for all Phase 1 debugging output instead of `fastframe_log`'s file-based logging. Revisit writable-directory resolution (likely via JNI `Context.getFilesDir()`/`getExternalFilesDir()`) only when a later phase actually needs persisted settings/history on Android.
**Phase to address:** Phase 1 (don't block on it), properly resolved whenever settings/session persistence is first needed on Android (likely Phase 4+).

### Pitfall 5: D-06 cites the wrong upstream PR number — verify against #3867, not #3847

**What goes wrong:** CONTEXT.md D-06 and the project's own `PITFALLS.md` both say to check the pinned fork against "PR #3847 (GL-resume crash fix)". **PR #3847 is titled "Fix Android crash on resume with `wgpu`" and only modifies `crates/eframe/src/native/wgpu_integration.rs`** `[VERIFIED: gh api repos/emilk/egui/pulls/3847/files]`. Spotifast's `eframe` feature list is `["accesskit", "glow", "default_fonts", "links", "wayland", "x11", "persistence"]` — **no `wgpu` feature is enabled.** The actually-relevant fix for a glow-only app is **PR #3867**, "Fix Android crash on resume with Glow backend", merged 2024-01-24, touching `crates/eframe/src/native/glow_integration.rs` exclusively `[VERIFIED: gh api repos/emilk/egui/pulls/3867/files and /pulls/3867]`. Both PRs close the same umbrella issue (#3674) and reference the same underlying regression from #3172 (multi-viewport work), but they are separate code changes in separate renderer backends.
**Why it happens:** egui's wgpu and glow renderer integrations are maintained as parallel, largely-duplicated code paths (`wgpu_integration.rs` / `glow_integration.rs`) for historical reasons — a fix in one does not imply a fix in the other, and GitHub issue cross-referencing (both PRs reference issue #3674) makes it easy to conflate them.
**How to avoid:** When the planner writes the D-06 verification task, cite PR #3867's merge commit (`200051d5d8fb3c384db21fe14d8318265c60c038`), not #3847's. This research already ran the ancestry check: `git merge-base --is-ancestor 200051d5d8fb3c384db21fe14d8318265c60c038 ba6790fe7cf46e58e8d27ce1524cbfdee745e938` returns **true** (exit 0) in the locally cached `crmne/egui` git database — **the pin is confirmed downstream of the correct fix.** D-06's audit conclusion (pin is safe) is unchanged; only the cited PR number needs correcting.
**Warning signs:** None at runtime — this is a documentation/audit-trail accuracy issue, not a build or runtime risk, since the actual commit ancestry is already confirmed correct.
**Phase to address:** Phase 1, when the planner writes the D-06 verification task's exact wording/evidence.

### Pitfall 6: `cpal`'s AAudio device enumeration cannot be validated by a host-side `cargo build`/`cargo check` alone

**What goes wrong:** A team might treat "compiles for `aarch64-linux-android`" as equivalent to "the cpal/AAudio spike passed." It is not. `cpal::Host::devices()` on Android calls `AudioDeviceInfo::request()`, which calls `ndk_context::android_context()` (needs a populated `AndroidContext`) and then does JNI calls through it. **Verified by reading `cpal-0.18.2/src/host/aaudio/mod.rs:179-189`:** if the JNI call fails (e.g., no context available, as in a standalone host-compiled binary with no `android_main`/`android-activity` runtime), `devices()` gracefully falls back to `vec![Device(None)]` — a single synthetic "Default Device" entry — rather than erroring. This fallback could be mistaken for "it enumerated a device, spike passed" when it has not actually exercised the real AAudio/JNI path at all.
**Why it happens:** `ndk_context`'s `AndroidContext` (the `JavaVM`/`Context` pair) is only populated by `android-activity` when a real `android_main` runs under the Android runtime — there is no way to populate it from a plain `cargo build --target aarch64-linux-android` host-side compile, by design.
**How to avoid:** D-05's spike must run the actual built APK on a real device or emulator (via `cargo apk run`) and inspect logcat output for a populated device list (e.g., log `AudioDeviceInfo` details, not just whether `devices()` returned `Ok`). A `Device(None)` fallback result should be treated as **spike failure**, not success — it means the JNI path was never actually exercised.
**Warning signs:** Spike "passes" by only checking `cpal::default_host().devices().is_ok()` rather than checking the list is non-empty *and* that at least one entry has a real device description (not the "Default Device" placeholder).
**Phase to address:** Phase 1 — write the spike's success check carefully per this nuance; this is also why D-05 explicitly requires an emulator/device (see Environment Availability — none is currently connected).

## Code Examples

### `android_main` wiring (source: `emilk/egui` `examples/hello_android`, current `main`)

```rust
use eframe::{CreationContext, egui};

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
        Box::new(|cc| Ok(Box::new(MinimalApp::new(cc)))),
    )
    .unwrap();
}
```
`#[unsafe(no_mangle)]` syntax (rather than bare `#[no_mangle]`) is required because spotifast's `Cargo.toml` already declares `edition = "2024"`, matching the official example's own `edition = "2024"` — no edition mismatch to worry about.

### cpal/AAudio tone-test spike (source: `fastframe-audio`'s own doc example, `crates/fastframe-audio/src/lib.rs`)

```rust
use fastframe_audio::{Output, OutputOptions, Render};

struct Tone { phase: f32, step: f32, channels: usize }
impl Render for Tone {
    fn configure(&mut self, sample_rate: u32, channels: u16) {
        self.step = 440.0 * std::f32::consts::TAU / sample_rate as f32;
        self.channels = usize::from(channels);
    }
    fn render(&mut self, out: &mut [f32]) {
        for frame in out.chunks_mut(self.channels) {
            self.phase = (self.phase + self.step) % std::f32::consts::TAU;
            frame.fill(self.phase.sin() * 0.1);
        }
    }
}

// Call this from inside android_main (or a thread spawned from it), AFTER
// android-activity has populated the JNI context -- not from a host binary.
let mut output = Output::open(
    OutputOptions::default(),
    Tone { phase: 0.0, step: 0.0, channels: 2 },
)?;
log::info!("audio device: {}", output.device_name());  // check this isn't "Default Device" in logcat
```

### Exact `cargo apk` invocations for the Phase 1 spikes

```bash
# Type-check only (fast iteration, caught the rfd blocker in this research):
cargo apk check --lib --no-default-features --target aarch64-linux-android

# Full build + install + run on a connected device/emulator, following logcat:
cargo apk run --lib --no-default-features -d <device-serial>
```

## State of the Art

| Old / stale claim | Corrected finding | How confirmed | Impact |
|--------------------|-------------------|----------------|--------|
| CONTEXT.md/PITFALLS.md: check pin against PR #3847 | The relevant fix for spotifast's `glow` backend is PR **#3867** | `gh api` diff inspection of both PRs + `git merge-base --is-ancestor` against the actual pinned commit | D-06's verification task should cite #3867; conclusion (pin is safe) unchanged |
| STACK.md: `eframe` 0.36.2 | Actually-resolved version in `Cargo.lock` is **0.36.1** | `grep Cargo.lock` | Cosmetic, but use the Cargo.lock value in any version-pinned documentation |
| docs.rs `cargo-apk` 0.10.0 page: "deprecated in favour of xbuild" | Still stale/wrong — `cargo-apk` git HEAD installs and runs cleanly today; `xbuild` remains self-described "(unmaintained)" | Actually ran `cargo install --git ... cargo-apk` successfully on this machine | Confirms D-01, no new information but now empirically verified rather than just cited |

**Deprecated/outdated:** None newly discovered beyond what project-level research already flagged (`xbuild`, `ndk-glue`).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Android application ID should be `rocks.spotifast.spotifast` (lowercased form of the existing Flatpak app ID `rocks.spotifast.Spotifast`) | Standard Stack / Architecture Patterns (Cargo.toml snippet) | Low — purely a naming/identity choice with no functional impact in Phase 1 (sideload-only debug APK, no store presence); easy to rename later. Flag for one-line user confirmation since no prior Android-specific ID decision exists in the project. |
| A2 | `links` eframe feature (pulls `webbrowser` crate) may or may not need dropping for the Android target — not yet verified by an actual compile attempt with it included | Architecture Patterns, Pattern 1 | Low-Medium — if `webbrowser` doesn't cross-compile for Android, it's an easy additional feature to drop from the Android-target `eframe` feature list; if it does compile, no action needed. Phase 1 execution should verify this directly (one more `cargo apk check` run) rather than guessing. |
| A3 | `directories` crate issue #83 (ProjectDirs returning None on Android) is still unresolved as of this research's date | Pitfall 4 | Low — even if it has since been fixed upstream, the recommended Phase 1 approach (use `android_logger`/logcat, don't depend on `AppDirs` resolving) remains correct and loses nothing; it's a conservative choice either way. |

## Open Questions

1. **Does the rest of the dependency graph compile cleanly once the `rfd` gate is added?**
   - What we know: Verified compilation proceeds correctly through `reqwest`, `tokio`, `rustls`, all three `librespot-*` forks, the patched `egui`/`winit` forks, `android-activity`, and `jni` before hitting the `rfd` wall. That's the vast majority of the dependency graph by crate count and the highest-risk crates (patched forks, FFI-heavy crates).
   - What's unclear: Whether anything beyond the `rfd` failure point (alphabetically/topologically later in the build order) also fails — the build stopped at the first hard error, so later-ordered crates were never reached.
   - Recommendation: Phase 1's first task should be exactly: add the `rfd` `cfg` gates, then re-run `cargo apk check --lib --no-default-features -F eframe/android-native-activity --target aarch64-linux-android` (or with the feature properly declared in `Cargo.toml`) to find out definitively, before planning further Phase 1 tasks around a "known-good" build.

2. **No Android device or emulator is currently connected** (confirmed again during this research: `adb devices` shows nothing, `emulator -list-avds` shows nothing).
   - What we know: The SDK has `system-images`/`emulator`/`platform-tools` directories present (per `ls ~/Android/Sdk`), so creating an x86_64 AVD is likely possible without new downloads, but this wasn't independently verified (no `system-images;android-34;...` package confirmed installed).
   - What's unclear: Whether a suitable system image is already installed for AVD creation, or needs downloading.
   - Recommendation: Surface this explicitly before Phase 1 execution reaches on-device success criteria (#3, #4, #5), per CONTEXT.md's own carried-forward open question. This is not something research/planning can resolve unilaterally.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Rust toolchain + Android targets | All of Phase 1 | ✓ | 1.98.0, `aarch64-linux-android` + `x86_64-linux-android` installed | — |
| Android SDK | Packaging, manifest tooling | ✓ | `~/Android/Sdk`, platforms `android-34` and `android-36.1` (no `android-35`) | — |
| Android NDK | Cross-compilation | ✓ | 27.0.12077973 (r27 LTS) | — |
| `adb` / platform-tools | Device install/run, AND-00 check | ✓ | present at `~/Android/Sdk/platform-tools` | — |
| `cargo-apk` | APK build/packaging | ✓ (installable, verified) | git HEAD `887423a9` (2025-07-09) | `cargo-apk2` per D-01's documented fallback |
| Physical device or AVD emulator | On-device success criteria #3/#4/#5, D-04, D-05 | ✗ | — | None — this blocks on-device verification entirely; must be resolved before those criteria can be checked (not a Phase 1 planning/code gap, an execution-environment gap) |
| `android_logger` crate | Phase 1 spike debugging | ✓ (not yet installed, verified available on crates.io, slopcheck `[OK]`) | 0.15.1 | — |

**Missing dependencies with no fallback:**
- A connected physical device or running emulator — blocks D-04, D-05, and success criteria #3-#5 outright. Must be resolved by the user/operator before those specific tasks execute; code-level Phase 1 work (Cargo.toml changes, `android_main`, the `rfd` gate) does not require it.

**Missing dependencies with fallback:**
- None beyond the device/emulator gap above.

## Security Domain

`security_enforcement` is absent from `.planning/config.json` (treated as enabled per protocol), but Phase 1 touches no authentication, credential storage, or network-facing code — it is pure build/packaging infrastructure plus two platform-lifecycle spikes. Most ASVS categories are not yet applicable; this phase is a placeholder for the categories that matter once Phase 4 (auth/credentials) and Phase 6 (background service) land.

| ASVS Category | Applies in Phase 1 | Note |
|---------------|---------|-----------------|
| V2 Authentication | No | No auth code touched this phase. |
| V3 Session Management | No | Same. |
| V4 Access Control | No | Same. |
| V5 Input Validation | No | No new user-facing input surfaces in Phase 1's minimal render. |
| V6 Cryptography | No | Same. |

**One Phase-1-relevant signing/packaging note (not an ASVS category, but a real security-adjacent fact):** `cargo-apk`'s `dev` build profile auto-generates a debug keystore at `$HOME/.android/debug.keystore` if one doesn't already exist `[VERIFIED: cargo-apk README excerpt]`. This is standard, expected behavior for a sideload-only debug APK (consistent with the project's explicit out-of-scope decision to skip Play Integrity/store signing) — no action needed, just documenting it so it isn't mistaken for a missing-config error during Phase 1 execution.

## Sources

### Primary (HIGH confidence — directly verified by running tools/reading source on this machine)
- `cargo install --git https://github.com/rust-mobile/cargo-apk --locked cargo-apk` — actually run; installed and confirmed working (`--help` output for `build`/`run`/`check`/`gdb`)
- `cargo apk check --lib --no-default-features [-F eframe/android-native-activity] --target aarch64-linux-android` against the real `spotifast` repo — actually run twice; found the `android-activity` feature requirement and the `rfd` blocker
- Standalone `cpal = "0.18.1"` cross-compiled for `aarch64-linux-android` — actually run; succeeded
- `cpal-0.18.2/src/host/aaudio/{mod.rs,java_interface/*.rs}` — read directly from `~/.cargo/registry/src/.../cpal-0.18.2`
- `rfd-0.17.2/src/backend.rs` — read directly from `~/.cargo/registry/src/.../rfd-0.17.2`
- `fastframe-audio`'s `Cargo.toml` and `src/lib.rs` — read directly from the cached git checkout `~/.cargo/git/checkouts/fastframe-97b28a4c4d990e78/0d65ca9`
- `crmne/egui@ba6790fe` (`crates/eframe/{epi.rs,lib.rs,Cargo.toml}`, `crates/egui-winit/Cargo.toml`) — read directly from `~/.cargo/git/db/egui-36521202101fc217` after `git fetch`
- `git merge-base --is-ancestor 200051d5d8fb3c384db21fe14d8318265c60c038 ba6790fe7cf46e58e8d27ce1524cbfdee745e938` — actually run, returned true
- `gh api repos/emilk/egui/pulls/{3847,3867,3676}` and `/pulls/{id}/files` — actual PR metadata and file diffs
- `rust-mobile/cargo-apk` source: `ndk-build/src/{manifest.rs,ndk.rs,apk.rs}` — read directly from the git-installed checkout
- `github.com/emilk/egui` `examples/hello_android/{Cargo.toml,src/lib.rs,src/main.rs}` — fetched directly via `gh api repos/.../contents/...`
- `docs.rs/android-activity/0.6.1` — official docs, fetched directly (lifecycle events, `ndk-context` auto-init, manifest requirements)
- `cargo info android_logger` — registry metadata, version 0.15.1
- `slopcheck install android_logger` — ran directly, `[OK]` verdict

### Secondary (MEDIUM confidence)
- `zff.dev/dirs/directories-rs/issues/83` ("No project directory on Android") — single GitHub issue, no confirmed-fixed status found; reasoning (use logcat instead) is conservative regardless of whether this is still open

### Tertiary (LOW confidence)
- None beyond what's already flagged inline above.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every version number and feature-gate claim verified against this repo's actual `Cargo.lock` or a direct source read, not training-data recall.
- Architecture: HIGH — the `android_main` pattern is copied verbatim from egui's own current canonical example, not synthesized.
- Pitfalls: HIGH — Pitfalls 1, 2, 3, 5, 6 were each independently reproduced/verified by running real tools; Pitfall 4 is MEDIUM (single upstream issue report, not independently reproduced on this machine since no device is connected).

**Research date:** 2026-10-14
**Valid until:** 7 days for the `cargo-apk` freshness/maintenance claim (D-01 already flags this as fast-moving and requiring live re-verification); 30 days for everything else (version pins, source-verified facts, the fork-commit ancestry check — these don't change without the project's own `Cargo.toml`/`[patch.crates-io]` changing first).

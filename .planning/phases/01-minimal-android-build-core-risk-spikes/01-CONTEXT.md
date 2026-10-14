# Phase 1: Minimal Android Build + Core Risk Spikes - Context

**Gathered:** 2026-10-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Get a debug APK that builds for `aarch64-linux-android`, installs on a real device/emulator, and renders a minimal egui surface — while retiring the two highest-blast-radius unknowns before any later phase depends on them: (1) whether the pinned `crmne/egui`/`crmne/winit` fork survives Android's GL-surface-destroyed-on-background/rotate lifecycle, and (2) whether `cpal` 0.18 (via `fastframe-audio`) has a working Android/AAudio backend at all. This phase does NOT touch UI content, desktop-only code stripping, login, or playback logic — those are later phases. Desktop build must stay green throughout (`cargo check`, existing tests).

</domain>

<decisions>
## Implementation Decisions

These are technical/infrastructure decisions with no real user-facing ambiguity (per discuss-phase philosophy, Claude's job, not the user's) — auto-selected in `--auto` mode using the project's own research as the "recommended" source. Logged here for audit.

### Packaging tool
- **D-01:** [auto] Packaging tool — Q: "cargo-apk (git HEAD) vs cargo-apk2 vs cargo-ndk+Gradle for Phase 1?" → Selected: "cargo-apk, installed from git HEAD (not crates.io 0.10.0, which is stale)" (recommended default per `.planning/research/STACK.md` — matches `emilk/egui`'s own current upstream Android example almost exactly, zero Gradle needed for Phases 1-5). Re-verify live maintenance status of `cargo-apk`/`cargo-apk2`/`cargo-ndk` at implementation time per PITFALLS.md's explicit warning that tool status "can shift quickly" — do not trust the research snapshot blindly.
- **D-02:** [auto] Packaging tool escalation path — Q: "Lock in Gradle/cargo-ndk now (Phase 1) since Phase 6 needs it, or defer?" → Selected: "Defer — use zero-Gradle `cargo-apk` for Phase 1, migrate to `cargo-ndk` + a minimal hand-written Gradle module only when Phase 6 needs Kotlin/`<service>` manifest support" (recommended: minimizes Phase 1 complexity; ARCHITECTURE.md's "Anti-Pattern 3" warning about picking a packager for Phase 1 simplicity alone is satisfied by explicitly documenting the escalation path now, not by setting up Gradle prematurely).

### Minimum SDK / target versions
- **D-03:** [auto] minSdk — Q: "What minSdk?" → Selected: "26 (Android 8.0)" (recommended: `cpal`'s AAudio-only backend hard-requires API 26; setting it correctly now avoids rediscovering this constraint during Phase 1's own cpal spike). targetSdk 34, matching the already-installed `platforms;android-34` SDK component.

### Risk spikes — scope and failure handling
- **D-04:** [auto] GL-resume spike — Q: "How to verify the egui/winit fork survives background/rotate?" → Selected: "Manual device test: lock screen, wait, unlock; rotate; background via Home button and return — confirm no crash/black screen, before marking Phase 1 success criterion #4 done" (per PITFALLS.md Pitfall 1 — this is a Phase-1-blocking requirement, not Phase 6 polish).
- **D-05:** [auto] cpal/AAudio spike — Q: "What counts as 'cpal works on Android'?" → Selected: "Compile `fastframe-audio`/cpal for `aarch64-linux-android`, enumerate at least one real output device via cpal's device-listing API, and play one test tone" (per PITFALLS.md Pitfall 3 and SUMMARY.md's Phase 1 success-criteria language). If this spike fails, STOP and surface to the user before continuing — a hand-written Oboe/AAudio JNI sink is real new platform code and is NOT assumed in-scope for Phase 1; it would need explicit scope approval (do not silently absorb it into this phase's plan).
- **D-06:** [auto] Fork-commit audit — Q: "How to confirm the pinned `crmne/egui`/`crmne/winit` commits include the upstream GL-resume fix (PR #3847)?" → Selected: "Check the pinned commit SHA in Cargo.toml's `[patch.crates-io]` against `emilk/egui`'s fix-PR merge commit/date before relying on D-04's manual test alone — if the pin predates the fix, flag it rather than assuming the manual test alone is sufficient proof" (per PITFALLS.md Pitfall 6 — `cargo check` succeeding doesn't prove the fix is present).

### Claude's Discretion
- Exact crate-type wiring for the Android entry point (the project already has both a `[lib]` target `src/lib.rs` and a `[[bin]]` target `src/spotifast.rs` — Claude/planner decides whether the Android `cdylib`/`android_main` entry point is added to the existing `[lib]` crate-type list or a new target, following `cargo-apk`'s conventions).
- Exact `eframe` feature flags to enable for Android (`android-native-activity` vs `android-game-activity` — STACK.md recommends starting with `android-native-activity`, escalating only if touch/IME input proves too limited in Phase 3).
- Where new Android module code lives (`src/android/` per the existing per-target module convention — `window.rs`, `power.rs`, etc. are the established pattern for platform-specific code).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project-level
- `.planning/PROJECT.md` — core value, constraints (desktop build must never break), out-of-scope boundaries
- `.planning/REQUIREMENTS.md` — AND-00, AND-01, AND-02 (this phase's requirements)
- `SPOTIFAST-ANDROID.md` §3, §6 (Fase 1), §7 (R1, R2, R3, R8, R9) — original PRD's environment/build-phase description and risk list

### Research (this phase's primary input)
- `.planning/research/STACK.md` — packaging tool comparison, eframe/winit Android feature flags, minSdk/NDK version table
- `.planning/research/PITFALLS.md` — Pitfalls 1 (GL resume), 3 (cpal/AAudio), 5 (packager choice), 6 (patched-fork cross-compilation) — all phase-1-relevant
- `.planning/research/ARCHITECTURE.md` — component boundary guidance, Anti-Pattern 3 (packager-choice-for-Phase-1-only)
- `.planning/research/SUMMARY.md` — "Phase 1" section under Implications for Roadmap

### Original project architecture (must read before touching entry point)
- `AGENTS.md` — existing architecture rules (`src/ui/` → `Action` → `app.rs`, backend/player off the UI thread)
- `src/entrypoint.rs` — current desktop `eframe::run_native`/`NativeOptions` setup this phase must not break
- `src/spotifast.rs` — current `[[bin]]` entry point
- `Cargo.toml` lines ~13-19 (`[lib]`/`[[bin]]` targets), ~35 (`eframe` feature list), ~274+ (`[patch.crates-io]` pinned fork commits)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/entrypoint.rs::run()` — existing desktop entry point calling `eframe::run_native`; Android's `android_main` will need an analogous but separate path, not a modification of this one (desktop must stay untouched).
- Existing per-target module pattern (`window.rs` for Windows-only APIs, `power.rs`, `mac_notch.rs`, etc.) — establishes the convention a new `src/android/` module family should follow.

### Established Patterns
- `[lib]` crate `src/lib.rs` (name `spotifast`) + separate `[[bin]]` crate `src/spotifast.rs` — the Android `cdylib` entry point most likely attaches to the `[lib]` target's crate-type list (cargo-apk convention), not the `[[bin]]`.
- `eframe` is currently `default-features = false` with an explicit feature list (`accesskit`, `glow`, `default_fonts`, `links`, `wayland`, `x11`, `persistence`) — Android features (`android-native-activity`) need to be added to this list behind `cfg(target_os = "android")`-aware `[target.'cfg(...)'.dependencies]` or a Cargo feature, not globally (would break desktop feature set).
- `[patch.crates-io]` already pins `eframe`/`egui-winit` to a specific `crmne/egui` commit (`ba6790fe7cf46e58e8d27ce1524cbfdee745e938`) — D-06 applies directly to this exact pin.

### Integration Points
- `build.rs` already has `#[cfg(windows)]`-gated platform logic (GLEW/vcpkg) — establishes precedent for adding `#[cfg(target_os = "android")]` build-script logic (e.g., NDK linking) in the same file rather than a new one.

</code_context>

<specifics>
## Specific Ideas

No specific UI/behavior requests for this phase — it's pure infrastructure. The one concrete constraint carried from the user's earlier setup work: the local dev environment (Rust 1.98.0, Android SDK command-line tools build 15859902, platform android-34, NDK 27.0.12077973) is already verified and should be treated as fixed — do not suggest Android Studio or a different NDK/SDK installation method.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

### Open question for the user (not a scope gray area, but a real blocker for success criterion #3)
No physical Android device or emulator (AVD) is currently connected (`adb devices` showed none during Fase 0's environment check). Phase 1 execution will need one of:
- A real Android phone connected via USB with developer/USB debugging enabled, or
- An AVD (x86_64 emulator image) created and started locally.
This wasn't asked during discussion because `--auto` mode skips interactive questions — the planner/executor should surface this explicitly before attempting the on-device success criteria (#3, #4, #5), since it can't be resolved automatically.

</deferred>

---

*Phase: 1-Minimal Android Build + Core Risk Spikes*
*Context gathered: 2026-10-14*

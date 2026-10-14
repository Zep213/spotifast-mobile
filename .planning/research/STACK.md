# Stack Research

**Domain:** Porting a Rust + egui (eframe/glow) desktop app to Android, keeping Rust/egui (no UI rewrite)
**Researched:** 2026-10-14
**Confidence:** MEDIUM-HIGH (core windowing/packaging findings verified against upstream `emilk/egui` repo, crates.io, and GitHub API metadata; Phase-6 JNI/Kotlin specifics are MEDIUM — smaller, less-verified tooling)

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `eframe` | 0.36.2 (already pinned) | App shell / window + GL context management | Already in use on desktop. Confirmed via `docs.rs/crate/eframe/0.36.2/features` to ship two Android-specific, opt-in Cargo features: `android-native-activity` and `android-game-activity`, both forwarding to `egui-winit`. No version bump needed. |
| `winit` (via `crmne/winit` fork, commit-pinned) | 0.30.x line (upstream `winit` is at 0.30.13 as of 2026-09-04) | Window/event-loop abstraction, Android entry point | Checked `crmne/winit` on GitHub: it is a straight fork of `rust-windowing/winit` (`fork: true`, `parent: rust-windowing/winit`), and its most recent commits are plain upstream commits (not divergent patches). Android support should behave identically to vanilla `winit` 0.30.x + `android-activity` 0.6.x. |
| `android-activity` | 0.6.1 (current, released 2026-03-24) | `winit`'s Android glue (NativeActivity/GameActivity entry point) | Pulled in transitively by `winit`/`egui-winit`; do not depend on it directly — version must match what the pinned `winit` fork expects, or you get the classic "two android-activity versions in the dependency tree" build break. |
| `glow` | 0.18.0 (current) | GL backend eframe already uses | No Android-specific concerns beyond standard EGL/GLES lifecycle handling (see Pitfalls below). Keep using it — do not switch to `wgpu` for the port; that would be a bigger, riskier change than the project's stated goal. |

### Packaging / Build Tooling

| Tool | Version / State | Purpose | Why Recommended |
|------|---------|---------|-----------------|
| `cargo-apk` | install from git (`rust-mobile/cargo-apk`), **not** the crates.io `0.10.0` release | Build + sign + install an APK straight from `cargo`, zero Gradle | This is literally what upstream `emilk/egui`'s own canonical Android example (`examples/hello_android`, README updated by PR #8122, merged into `main` Apr 2026) uses, with the exact same `eframe` 0.36-era, `glow`-backend, Rust-1.9x-era stack as spotifast. Confirmed via GitHub API: the repo is **not archived**, received a real fix commit as recently as **2025-07-09** (bumping `android-activity`/`android-logger` to resolve a NULL-pointer panic), and had its `target_sdk_version` default bumped to 35 in July 2025. The "deprecated in favour of xbuild" notice you'll find on `ndk-build`'s crates.io page is stale — `xbuild` itself is now the one labeled unmaintained (see below) and egui's maintainers did not migrate to it. |
| `cargo-apk2` (`mzdk100/cargo-apk2`) | 1.4.2 (published 2026-09-29) | Drop-in fork of `cargo-apk` with Java/Kotlin/Groovy/Scala source compilation, multi-activity/multi-service manifest entries, `manifest_override` escape hatch | **Fallback / Phase-6 escape valve.** Use if mainline `cargo-apk` hits the known `cargo-subcommand` parsing bug (issue `rust-mobile/cargo-subcommand#29`, closed 2025-07-05 — should be fixed in current `cargo-apk` git HEAD, but `cargo-apk2` sidesteps it entirely) or once you need to compile a small Kotlin `Service`/`MediaSession` class without adopting a full Gradle project (see "Stack Patterns by Variant" below). Single-maintainer project — treat as MEDIUM confidence, validate early. |
| `cargo-ndk` (`bbqsrc/cargo-ndk`) + a minimal hand-written Gradle module | 4.1.2 (released 2025-08-09; repo pushed as recently as 2026-10-10, 974 stars) | Cross-compile the Rust `cdylib` into a standard Android `jniLibs/` tree; **does not build an APK by itself** | By far the most actively maintained of the four tools evaluated. This is the standard, professional pattern once an app needs real Android-platform glue: a Kotlin `MediaSessionService`, `androidx.media3` (Maven-resolved) dependencies, R8/ProGuard, and AGP's manifest merger validating `android:foregroundServiceType`. Real-world precedent: the MPD-Android project bridges a native (non-JVM) player core to a Kotlin `MediaSessionService` using exactly this split (native `.so` + thin Gradle/Kotlin shell). Combine with the community Gradle plugin `com.github.willir.rust.cargo-ndk-android` (adds `buildCargoNdkDebug`/`Release` tasks) rather than hand-rolling the Gradle↔cargo glue. |

### What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `xbuild` (`rust-mobile/xbuild`) | Its own GitHub repo description (verified via `gh api repos/rust-mobile/xbuild`, not a mirror) literally reads **"Cross compile rust to any platform (unmaintained)"**. It still gets sporadic commits (last 2025-08-15) but has PRs open and unmerged since 2023–2024 (e.g. #173, "Better instructions... Moving from Cargo-APK", open since March 2024). It is *not* what egui's own upstream example uses. Several web sources claim it's "the recommended successor to cargo-apk," but that claim is contradicted by egui's actual current example and by the repo's own self-description. | `cargo-apk` (Phase 1-5) → `cargo-ndk` + Gradle (Phase 6+) |
| `ndk-glue` / pre-0.28 `winit` Android backend | Superseded by `android-activity` since `winit` 0.28 (2023). Mixing `ndk-glue`-era crates with a modern `android-activity`-based `winit` causes duplicate-symbol / entry-point conflicts. | `android-activity` 0.6.x via `winit`/`egui-winit`'s re-export — never depend on `android-activity` directly, let `winit` pin the version. |
| `cargo-apk` 0.10.0 from crates.io as the *only* source | That release is from **2023-11-30**; it predates the `cargo-subcommand` bug fix (closed 2025-07-05) and the `target_sdk_version` default bump (2025-07-05). Relying on the stale crates.io release risks hitting already-fixed bugs. | `cargo install --git https://github.com/rust-mobile/cargo-apk cargo-apk` to track the maintained git HEAD, same as egui's own `hello_android` README recommends (it pins a patched fork for the same reason). |
| Switching to `wgpu` renderer "because it's the Android-recommended path" | Not true — both `glow` and `wgpu` are first-class eframe Android backends (both appear as opt-in-adjacent features: `glow` is a plain feature, `wgpu` ships in eframe's `default` feature set). Switching renderers is an unrelated, much larger risk than this port needs. | Keep `glow`; just budget time for the EGL-context-loss testing described in Pitfalls. |
| `androidx.media3` as a first assumption for Phase 6 | Requires Gradle + Google's Maven repo resolution — not available from `cargo-apk`/`cargo-apk2`'s zero-Gradle model. Pulling it in means committing to the `cargo-ndk` + Gradle migration *before* you've confirmed you actually need it. | Start Phase 6 with plain `android.app.Service` + `android.media.session.MediaSession` + `android.app.Notification.Builder` (zero Maven deps, compiles as a `kotlin_sources` entry under `cargo-apk2`); only migrate to `cargo-ndk` + Gradle + `androidx.media3` if that proves insufficient. |

## Installation

```bash
# Rust Android targets (already done per AND-00 env check)
rustup target add aarch64-linux-android x86_64-linux-android

# Packaging tool — Phase 1 through Phase 5 (no Gradle)
cargo install --git https://github.com/rust-mobile/cargo-apk cargo-apk
# Fallback if the above still hits the cargo-subcommand bug, or once you need
# Kotlin sources / extra <service> manifest entries (Phase 6 attempt #1):
cargo install cargo-apk2

# Only if Phase 6's zero-Gradle attempt is insufficient (see Stack Patterns):
cargo install cargo-ndk
# + add a minimal app/ Gradle module with the
#   com.github.willir.rust.cargo-ndk-android Gradle plugin
```

```toml
# Cargo.toml — Android-specific eframe feature set, mirroring eframe's own
# upstream hello_android example (examples/hello_android/Cargo.toml, main branch):
[target.'cfg(target_os = "android")'.dependencies]
eframe = { workspace = true, default-features = false, features = [
    "default_fonts",
    "glow",
    "android-native-activity",
] }
# NOTE: do NOT inherit the desktop target's `wayland`/`x11`/`wgpu`(default)
# features into the Android build — desktop keeps its own feature list under
# [target.'cfg(not(target_os = "android"))'.dependencies] or the existing
# top-level [dependencies] entry, unchanged.

[lib]
crate-type = ["cdylib", "lib"]  # cdylib required for Android, lib for desktop
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|--------------------------|
| `cargo-apk` (git HEAD) | `cargo-apk2` | From day one, if you want Kotlin/Java source support available early rather than bolted on later, or if `cargo-apk` git HEAD still shows the `cargo-subcommand` glob bug on your toolchain. |
| `cargo-apk`/`cargo-apk2` (Phases 1-5) | `cargo-ndk` + Gradle | As soon as Phase 6 needs a dependency that only exists on Maven (e.g. you decide `androidx.media3` is worth the migration over plain `android.media.session.MediaSession`), or if `manifest_override` proves too fragile for `android:foregroundServiceType` across Android 14/15/16 test devices. |
| `android-native-activity` feature | `android-game-activity` feature | If touch/IME input handling under plain `NativeActivity` proves too limited for the ported touch UI (Phase 3) — `android-activity`'s own docs note `GameActivity` gets more sophisticated input handling over time, at the cost of requiring a Maven-resolved `androidx.games:game-activity` AAR (i.e. forces the Gradle migration early). |
| `glow` (existing) | `wgpu` (eframe's default) | Not recommended for this port — would be a parallel, higher-risk rewrite of the rendering backend with no clear Android-specific benefit; only consider if `glow`'s EGL-context-loss issues (see Pitfalls) prove unfixable in practice. |

## Stack Patterns by Variant

**If Phase 1-5 (build, demo mode, touch UI, login, audio playback) — no custom native-Android UI needed:**
- Use `cargo-apk` (git HEAD), `android-native-activity`, `glow`.
- Zero Gradle, zero Java/Kotlin. Matches upstream egui's own tested configuration exactly.
- Login's OAuth redirect-back-to-app (R5) can be handled with a manifest `<intent-filter>` for a custom URI scheme — `cargo-apk2` supports declaring `intent_filter` blocks if `cargo-apk`'s plain manifest schema isn't expressive enough; this still doesn't require Gradle.

**If Phase 6 (foreground service, MediaSession, lock-screen/headset controls — AND-07/AND-08):**
- Attempt 1 (lower cost): stay on `cargo-apk2`. Write the foreground `Service` + `android.media.session.MediaSession` + `android.app.Notification.Builder` as Kotlin via its `kotlin_sources` option; declare the `<service>` with `manifest_override` to add `android:foregroundServiceType="mediaPlayback"` plus the `FOREGROUND_SERVICE`/`FOREGROUND_SERVICE_MEDIA_PLAYBACK` permissions (mandatory on `targetSdkVersion >= 34`, verified against `developer.android.com/about/versions/14/changes/fgs-types-required`). JNI calls from Kotlin into the Rust player core go through the `jni` crate, same mechanism `cpal`'s own Android notes describe (`ndk_context::initialize_android_context` from `JNI_OnLoad` if the context isn't already set by `android-activity`).
- Attempt 2 (fallback, higher cost but more standard): migrate to `cargo-ndk` + a minimal Gradle `app/` module, pull in `androidx.media3-session` from Google's Maven repo, and follow the MediaSessionService pattern Google documents (`developer.android.com/media/media3/session/background-playback`). Trigger this migration if Attempt 1's manifest/permission combination doesn't pass validation on an Android 14+ test device, or if the team decides `androidx.media3`'s notification/lock-screen polish is worth the one-time Gradle setup cost.
- Either way, keep the native Rust player core (`src/backend.rs`, `src/player.rs`) oblivious to which packaging tool is in play — only the thin JNI/Kotlin shell changes between the two attempts.

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| `eframe` 0.36.2 | `winit` 0.30.x / `android-activity` 0.6.x | Confirmed via crates.io metadata dates (`winit` 0.30.13 published 2026-09-04, `android-activity` 0.6.1 published 2026-03-24, `eframe` 0.36.2 published 2026-09-08) — all current as of research date, no known incompatibility. |
| `cpal` 0.18 (via `fastframe-audio`) | Android minSdk **26** (Android 8.0) | Verified from `RustAudio/cpal`'s own README: "Minimum version: Android 8.0 (API 26)", AAudio-only backend on Android (no OpenSL ES fallback documented). This is a **harder floor than eframe's own example** (which defaults `min_sdk_version = 23`) — use 26, not 23, since spotifast's core value requires real audio playback (AND-06). |
| `android:foregroundServiceType` manifest attribute | `targetSdkVersion >= 34` | Only enforced (and only needed) once you target API 34+; recommend `targetSdk`/`compileSdk` **34** (matches the `platforms;android-34` already installed per the local env check in `PROJECT.md`) so Phase 6 exercises the real, current foreground-service validation path without forcing an SDK platform re-download. Bump to 35/36 only if a chosen packaging tool's own default forces it (`cargo-apk2` defaults to `target_sdk_version = 37`, auto-capped to whatever platform is actually installed). |
| NDK | Keep **27.0.12077973** (already installed, r27 LTS) | GitHub Actions' own CI policy made r27 the default baseline starting 2026-01-12 ("N, N-1, and latest LTS before them"); AGP 9.4's own default is a newer r28 (28.2.13676358), and egui's own `hello_android` README currently tests against r29 (29.0.14206865) — but neither is a hard requirement. Don't upgrade preemptively; the project's own "no new dependency without a stated reason" rule applies equally to toolchain churn. Re-evaluate only if a build error explicitly names a missing NDK feature. |
| AGP (only relevant if/when the Phase-6 `cargo-ndk` + Gradle path is taken) | Gradle 9.6.0, JDK 17, compileSdk ≤ 37 | Latest stable AGP is **9.4.0** (Sept 2026, per `developer.android.com/build/releases/gradle-plugin`). Given the `cargo-ndk-android` Gradle plugin and most tutorials/StackOverflow coverage still target the AGP 8.x line, prefer a recent **AGP 8.9–8.13** release for the minimal Gradle module if you reach this point, rather than chasing the brand-new 9.x major version on a project whose Gradle usage is otherwise minimal. |

## Sources

- `docs.rs/crate/eframe/0.36.2/features` — confirmed full eframe 0.36.2 feature list (android-native-activity, android-game-activity, glow, wgpu, wayland, x11 as separate opt-in/default features). HIGH confidence.
- `github.com/emilk/egui` (`examples/hello_android/{README.md,Cargo.toml,src/lib.rs}`, current `main` branch, PR #8122 merged Apr 2026) — canonical, currently-tested upstream Android build recipe for eframe/glow. HIGH confidence.
- `github.com/emilk/egui` issues #3674 (closed, fix referenced #3676) and #3861 (closed 2024-01-24, confirms the specific "Home button then return" glow/Android crash was fixed on master) — verified via `gh api`. HIGH confidence for "fixed", MEDIUM for "no regressions since," since no exhaustive current-issue sweep was done.
- `github.com/rust-mobile/cargo-apk` + `github.com/rust-mobile/cargo-subcommand` issue #29 — verified via `gh api` (not archived, commits through 2025-07-09, bug closed 2025-07-05). HIGH confidence.
- `github.com/rust-mobile/xbuild` — verified via `gh api repos/rust-mobile/xbuild` (`description: "...(unmaintained)"`, open stale PRs). HIGH confidence this is the project's own self-assessment.
- `github.com/bbqsrc/cargo-ndk` + `github.com/mzdk100/cargo-apk2` (READMEs fetched directly) — MEDIUM confidence on the Kotlin/Java source and manifest-override details, since no hands-on build was performed as part of this research.
- `github.com/RustAudio/cpal` README — Android minSdk 26 / AAudio backend / `ndk_context` initialization requirement. HIGH confidence.
- `developer.android.com/about/versions/14/changes/fgs-types-required` — `android:foregroundServiceType` mandatory on targetSdk 34+, `MissingForegroundServiceTypeException` otherwise. HIGH confidence (official docs).
- `developer.android.com/build/releases/gradle-plugin` — AGP 9.4.0 current stable, Gradle 9.6.0, NDK 28.2.13676358 default. HIGH confidence (official docs, fetched directly).
- `github.com/crmne/winit`, `github.com/crmne/egui` (`gh api repos/...`) — confirmed both are straight, non-divergent forks of `rust-windowing/winit` and `emilk/egui` respectively, actively synced as of Oct 2026. MEDIUM confidence (only checked the last 8 commits, not full fork history).
- MPD-Android project (`git.pvv.ntnu.no/oysteikt/mpd`) — cited as real-world precedent for a native player core bridged to a Kotlin `MediaSessionService`. LOW-MEDIUM confidence (single community example, not an official pattern).

---
*Stack research for: Rust + egui (eframe/glow) desktop-to-Android port — packaging/windowing dimension*
*Researched: 2026-10-14*

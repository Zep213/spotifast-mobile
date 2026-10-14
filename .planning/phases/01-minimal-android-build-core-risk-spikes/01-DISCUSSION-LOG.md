# Phase 1: Minimal Android Build + Core Risk Spikes - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-10-14
**Phase:** 1-Minimal Android Build + Core Risk Spikes
**Areas discussed:** Packaging tool, Packaging tool escalation path, minSdk/targetSdk, GL-resume spike scope, cpal/AAudio spike scope, fork-commit audit

Run in `--auto` mode: no interactive questions asked. For each area, the recommended option from the project's own research (`.planning/research/`) was auto-selected and logged below for audit.

---

## Packaging tool

| Option | Description | Selected |
|--------|-------------|----------|
| cargo-apk (git HEAD) | Zero-Gradle, matches egui's own upstream Android example | ✓ |
| cargo-apk2 | Kotlin/manifest-richer fallback, less hands-on verified | |
| cargo-ndk + Gradle | Full flexibility but more setup, needed eventually for Phase 6 | |
| xbuild | docs.rs calls it the "successor" to cargo-apk | — ruled out, GitHub repo self-describes as unmaintained |

**Auto-selected:** cargo-apk, installed from git HEAD (not the stale crates.io 0.10.0 release).
**Notes:** STACK.md and PITFALLS.md both flag packaging-tool maintenance status as fast-moving — re-verify live status at implementation time rather than trusting this snapshot.

---

## Packaging tool escalation path

| Option | Description | Selected |
|--------|-------------|----------|
| Defer Gradle to Phase 6 | Start zero-Gradle with cargo-apk now, migrate only when Phase 6 needs Kotlin/`<service>` | ✓ |
| Set up Gradle/cargo-ndk now | Avoid a later migration, at the cost of more Phase 1 setup complexity | |

**Auto-selected:** Defer — keep Phase 1 zero-Gradle.
**Notes:** ARCHITECTURE.md's Anti-Pattern 3 warning (don't pick a packager for Phase 1 simplicity alone) is satisfied by documenting the escalation path explicitly in CONTEXT.md, not by setting up Gradle prematurely.

---

## Minimum SDK / target versions

| Option | Description | Selected |
|--------|-------------|----------|
| minSdk 23 (eframe example default) | Matches upstream egui's own example | |
| minSdk 26 | Required floor for cpal's AAudio-only backend | ✓ |

**Auto-selected:** minSdk 26, targetSdk 34 (matches installed `platforms;android-34`).
**Notes:** Setting minSdk correctly now avoids rediscovering the cpal constraint mid-Phase-1.

---

## GL-resume spike — what counts as "done"

| Option | Description | Selected |
|--------|-------------|----------|
| Manual device test (lock/unlock, rotate, background/return) | Real-device verification before marking success criterion #4 done | ✓ |
| Trust `cargo check` passing as sufficient | Faster but doesn't actually prove the GL-resume fix is present | |

**Auto-selected:** Manual device test required.
**Notes:** Per PITFALLS.md Pitfall 1 — Phase-1-blocking, not Phase 6 polish.

---

## cpal/AAudio spike — what counts as "done", and what happens on failure

| Option | Description | Selected |
|--------|-------------|----------|
| Compile + enumerate device + play test tone | Concrete, falsifiable success bar | ✓ |
| Compile only (no device/tone test) | Weaker signal, could hide a non-functional backend | |
| If it fails: silently absorb a hand-written Oboe/AAudio JNI sink into Phase 1 scope | Keeps moving but balloons scope without approval | |
| If it fails: stop and surface to the user before continuing | Protects scope — a JNI audio sink is real new platform code | ✓ |

**Auto-selected:** Compile + enumerate + test tone as the success bar; STOP and surface to the user if it fails, rather than silently expanding scope.
**Notes:** Per PITFALLS.md Pitfall 3 and SUMMARY.md's explicit Phase 1 success-criteria language.

---

## Fork-commit audit (crmne/egui, crmne/winit pins)

| Option | Description | Selected |
|--------|-------------|----------|
| Check pinned commit SHA against egui's GL-resume fix PR (#3847) merge date | Confirms the fix is actually present, not just that it compiles | ✓ |
| Rely on the manual device test alone | Faster, but `cargo check` succeeding doesn't rule out an un-advanced fork commit | |

**Auto-selected:** Check the pin explicitly, in addition to the manual device test.
**Notes:** Per PITFALLS.md Pitfall 6.

---

## Claude's Discretion

- Exact crate-type wiring for the Android entry point (existing `[lib]` vs new target)
- `android-native-activity` vs `android-game-activity` eframe feature choice (start with native-activity per STACK.md)
- Location of new Android module code (`src/android/`, following the existing per-target module convention)

## Deferred Ideas

None — discussion stayed within Phase 1 scope.

**Flagged (not deferred, but not resolvable in `--auto` mode):** No physical Android device or emulator is currently connected. This blocks on-device success criteria (#3, #4, #5) and needs the user's input before execution — see CONTEXT.md's `<deferred>` section.

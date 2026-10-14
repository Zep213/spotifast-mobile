# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-14)

**Core value:** Um APK de debug que abre, faz login, navega pela biblioteca, busca, toca música via streaming (Premium) e continua tocando com a tela apagada — sem quebrar o build desktop existente.
**Current focus:** Phase 1 — Minimal Android Build + Core Risk Spikes

## Current Position

Phase: 1 of 7 (Minimal Android Build + Core Risk Spikes)
Plan: 0 of TBD in current phase
Status: Ready to plan
Last activity: 2026-10-14 — Roadmap created from requirements + domain research

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: - min
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: -
- Trend: -

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Pre-Phase 1: Port keeps Rust + egui (no Kotlin UI rewrite) — preserves existing architecture
- Pre-Phase 1: No offline download/cache of Spotify audio — would circumvent service protection, violates upstream AGENTS.md
- Pre-Phase 1: Local Android dev environment via SDK command-line tools only (no Android Studio); Rust 1.98.0 + aarch64/x86_64-linux-android targets confirmed working 2026-10-14

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 1: Packaging tool (cargo-apk git HEAD vs. cargo-apk2 vs. cargo-ndk+Gradle) must be re-verified live at decision time — research flags this as a fast-moving target; must also confirm the chosen tool can compile Kotlin and declare `<service>` manifest entries for Phase 6
- Phase 1: cpal 0.18's Android/AAudio support is unverified for this exact version — spike required before Phase 5 playback work; hand-written Oboe/AAudio JNI sink is the budgeted fallback
- Phase 1: Pinned `crmne/egui`/`crmne/winit` fork commits must be confirmed downstream of upstream egui PR #3847 (GL-resume crash fix) before the phase is considered done
- Phase 4: `keyring-core` has no ready-made Android `CredentialStore` provider (`android-keyring` targets the incompatible older `keyring` trait family) — first-party implementation budgeted, re-check at Phase 4 start in case this has closed
- Phase 4: librespot's OAuth loopback flow is unvalidated for Android's browser-to-app handoff and Spotify's redirect-URI policy — needs an early spike with custom-URI-scheme as fallback
- Phase 6: Platform `MediaSession` vs. `androidx.media3.session.MediaSessionService` is an explicit judgment call to make at phase start, not mid-phase — determines whether Gradle/Maven dependencies become necessary
- Phase 6: API 34 requires `android:foregroundServiceType="mediaPlayback"` + `FOREGROUND_SERVICE_MEDIA_PLAYBACK` permission from the first commit — compile-invisible, runtime-only failure if missing
- OEM-specific battery-optimization killing of foreground services (Samsung/Xiaomi/etc.) is a known, unfixable-in-app ecosystem limitation — documented, not solved

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: 2026-10-14
Stopped at: ROADMAP.md and STATE.md created; REQUIREMENTS.md traceability already complete (11/11 requirements mapped to Phases 1-6, Phase 7 is cross-cutting verification)
Resume file: None

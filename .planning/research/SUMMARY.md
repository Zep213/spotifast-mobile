# Project Research Summary

**Project:** Spotifast Android
**Domain:** Desktop-to-mobile port of a Rust + egui (eframe/glow) native Spotify client, keeping the existing UI framework and adding Android platform glue (packaging, touch, background audio, Keystore credentials)
**Researched:** 2026-10-14
**Confidence:** MEDIUM-HIGH

## Executive Summary

This is a **platform port, not a rewrite**: the existing `eframe`/`egui`/`glow` desktop UI, the `librespot`-based playback engine (`src/backend.rs`, `src/player.rs`), and the `cpal`-based audio sink stay architecturally unchanged. Android support is added as one more `cfg(target_os = "android")` module family (`src/android/`), mirroring how the codebase already isolates platform code (`tray`, `window.rs`, `power.rs`, etc.), plus a deliberately minimal Kotlin shim (a single `PlaybackService` class, ~100-200 LOC) for the handful of Android APIs — foreground service, `MediaSession.Callback`, `AudioManager.OnAudioFocusChangeListener` — that require subclassing a Java base class and therefore cannot be called directly from Rust via JNI. Everything else (AudioManager lookups, NotificationManager, `java.security.KeyStore` for credentials) is callable straight from Rust through the `jni` crate + `ndk-context`, which `android-activity` (winit's Android glue) already wires up before `android_main` runs. `eframe` 0.36.2 ships Android support out of the box (`android-native-activity`/`android-game-activity` features), so no framework version bump is needed, and egui's own upstream `hello_android` example is a close structural match to this project's existing `glow`-backend stack.

The recommended approach is **`cargo-apk` (git HEAD, not the stale crates.io 0.10.0 release) for Phase 1's zero-Gradle minimal build**, deferring the Gradle/`cargo-ndk` migration until Phase 6 actually needs it for the Kotlin `PlaybackService` and `android:foregroundServiceType` manifest declaration — `cargo-apk2` is the identified fallback if `cargo-apk`'s known `cargo-subcommand` parsing bug resurfaces or Kotlin-source compilation is needed earlier than expected. Critically, architecture research recommends deciding the **packaging tool with Phase 6 in mind from day one** (prefer `cargo-ndk` + a minimal hand-written Gradle module if build complexity in Phase 1 proves acceptable), since discovering mid-project that the chosen tool can't declare a `<service>` manifest element or compile Kotlin would force a disruptive migration.

The single biggest risk cluster is **Android's process/surface lifecycle, which has no desktop analog**: (1) the GL surface is destroyed and must be fully rebuilt on every screen-off/backgrounding/rotation — egui/eframe itself had exactly this class of crash (fixed upstream by PR #3847, but the project's pinned `crmne/egui`/`crmne/winit` forks must be verified to include that fix); (2) a foreground service alone does not guarantee survival through Doze or OEM battery managers, and Android 14 (API 34, this project's target) throws a hard, compile-invisible crash (`MissingForegroundServiceTypeException`) if `android:foregroundServiceType="mediaPlayback"` and the matching permission aren't declared from the first commit; (3) `cpal`'s Android/AAudio support is unverified for this exact version and must be spiked early (Phase 1) rather than assumed, since a failure here reshapes Phase 5 significantly; and (4) `librespot-oauth`'s loopback-HTTP-server auth flow was built for desktop and needs explicit on-device validation in Phase 4, with a custom-URI-scheme fallback as a realistic contingency. All four risks are addressable, but only if front-loaded into the phases where they're cheapest to discover (Phase 1 spikes for GL resume and cpal/AAudio; Phase 4 spike for OAuth; Phase 6 manifest correctness from the first commit).

## Key Findings

### Recommended Stack

The core rendering/windowing stack needs almost no changes: `eframe` 0.36.2 (already pinned) ships Android support natively via opt-in features, `winit` (via the pinned `crmne/winit` fork, a clean non-divergent fork of upstream) pairs with `android-activity` 0.6.x for the NativeActivity/GameActivity entry point, and `glow` (already in use) stays the GL backend — switching to `wgpu` would be an unrelated, higher-risk rewrite with no Android-specific benefit. The packaging layer is where real decisions live: `cargo-apk` (git HEAD) is the tool egui's own canonical Android example uses and requires zero Gradle for Phases 1-5, with `cargo-apk2` as a Kotlin/manifest-richer fallback and `cargo-ndk` + a minimal Gradle module as the standard escape valve once Phase 6's foreground service / `MediaSession` / `androidx.media3` needs exceed what a Gradle-free tool can declare. `xbuild`, despite being docs.rs's suggested "successor" to `cargo-apk`, is explicitly self-described as unmaintained on GitHub and should not be used — this is flagged as a stale-docs trap in both STACK.md and PITFALLS.md independently.

**Core technologies:**
- `eframe` 0.36.2 (pinned, unchanged): app shell / GL context management — ships `android-native-activity`/`android-game-activity` features natively, no version bump needed
- `winit` (`crmne/winit` fork) + `android-activity` 0.6.1: window/event-loop + Android entry-point glue — confirmed clean, non-divergent fork; let `winit` pin `android-activity`'s version, never depend on it directly
- `glow` 0.18.0 (unchanged): GL rendering backend — keep as-is; do not switch to `wgpu`
- `cargo-apk` (git HEAD): zero-Gradle APK build/sign/install for Phases 1-5, matching egui's own upstream example; `cargo-apk2` and `cargo-ndk`+Gradle are the documented fallback/escalation path for Phase 6

### Expected Features

Scope is explicitly **Android platform integration**, not new Spotify features — the app is streaming-only by design (no offline cache), and research confirms this constraint does not block any table-stakes Android media feature (MediaSession/foreground-service contracts are source-agnostic); it does, however, elevate network-loss/reconnect handling to table-stakes priority since there's no cache to fall back on. A large portion of the generic "ship a real Android app" checklist (Play Integrity, AAB bundles, crash telemetry, in-app review, accessibility audits, Android Auto's Play design review) is explicitly **not needed** because this is a sideloaded, never-published, single-user debug APK — these are store-compliance costs, not platform requirements, and FEATURES.md documents them explicitly so they don't silently creep into the roadmap.

**Must have (table stakes — maps to AND-07/AND-08/AND-09):**
- Foreground Service with `mediaPlayback` type — without it, the OS kills the process within seconds of backgrounding
- `MediaSession` + MediaStyle notification (transport controls, art, metadata) — the only supported surface for lock-screen/Bluetooth/headset controls
- `POST_NOTIFICATIONS` runtime permission (API 33+) — foreground service notification silently fails to show without it
- Audio focus request/duck/pause + `ACTION_AUDIO_BECOMING_NOISY` handling — avoids the two most jarring "app isn't finished" bugs on Android (audio overlapping calls, blasting through speaker on headphone unplug)
- Network loss/reconnect + buffering state surfaced to MediaSession — elevated to P1 specifically because of the no-offline-cache constraint

**Should have (lower priority, add when convenient):**
- Audio output route change handling (Bluetooth connect mid-session) — mostly falls out of the becoming-noisy work and `cpal`/AAudio device-change handling

**Defer (explicitly out of scope for this milestone):**
- Android Auto / Automotive OS support, home-screen widget, App Actions/voice integration — real features but no audience for a never-published personal app, and Android Auto specifically conflicts with the "smallest native surface" goal (PRD R7)
- Edge-to-edge display, predictive back, splash screen, adaptive icon — pure visual polish, not required to avoid a "broken" feel
- Every Play Store compliance item (Play Integrity, AAB, Play Billing, Crashlytics/telemetry — the last explicitly forbidden by AGENTS.md anyway, Data Safety forms, ProGuard/R8 for size) — not applicable to a sideloaded debug build

### Architecture Approach

The Rust core stays a single process with one `backend.rs`/`player.rs` tokio runtime initialized once per process (not per-Activity), reachable from two independent Android entry points — the `MainActivity`/`android_main` UI thread and the Kotlin `PlaybackService` — that must be treated as peers, not parent/child, since Android can destroy/recreate the Activity independently of the Service. New Android-specific code lives entirely in a new `src/android/` module family, split into Rust-calls-Java-directly code (`jni_bridge.rs`, `credentials_android.rs` — no subclassing needed, use `jni` + `ndk-context`) and Java-calls-Rust code (`service_bridge.rs`, exported `Java_<pkg>_<Class>_<method>` functions that the one Kotlin `PlaybackService` class forwards to). The architecture research found a real gap worth flagging for Phase 4: the one maintained Android-Keystore crate (`android-keyring`) targets the older `keyring` crate's trait family, not the `keyring-core` traits this project already depends on — a first-party `CredentialStore` impl will likely need to be hand-written, using `android-keyring` only as a JNI-call reference.

**Major components:**
1. `src/android/jni_bridge.rs` — Rust→Java calls for AudioManager, NotificationManager, KeyStore (Pattern 1: no Kotlin subclass needed)
2. `src/android/service_bridge.rs` — exported JNI entry points the Kotlin `PlaybackService` calls into (Pattern 2 boundary, Java→Rust), pure translation layer with no business logic
3. `PlaybackService` (Kotlin, ~100-200 LOC, the only new Kotlin class) — owns the real `android.app.Service`, `MediaSession`/`MediaSession.Callback`, foreground notification, and `AudioManager.OnAudioFocusChangeListener`, because these specifically require subclassing a Java base class or implementing a callback interface
4. `src/android/credentials_android.rs` — new `keyring-core` `CredentialStore` arm backed by `java.security.KeyStore` ("AndroidKeyStore" provider), parallel to the existing macOS/Windows/Linux arms in `credentials.rs`
5. `src/backend.rs`/`src/player.rs` (unchanged) — existing tokio runtime and playback engine; Android only adds new callers, never new logic here

### Critical Pitfalls

1. **GL surface/context destroyed on every background/rotate** — egui/eframe itself had this exact crash class (fixed upstream by PR #3847); verify the pinned `crmne/egui`/`crmne/winit` fork commits are downstream of that fix before Phase 1 is considered done, and treat the lock/unlock/rotate cycle as a Phase 1 blocking requirement, not Phase 6 polish.
2. **Foreground service alone is not a Doze/OEM-battery-manager guarantee, and API 34 requires `android:foregroundServiceType="mediaPlayback"` + `FOREGROUND_SERVICE_MEDIA_PLAYBACK` permission or `startForeground()` throws immediately** — declare both from the very first Phase 6 commit; this is compile-invisible and only fails at runtime.
3. **`cpal` has no confirmed working Android/AAudio backend for this exact version** — this is a packaging/platform-support question, not a tuning problem; spike it in Phase 1 (compile `fastframe-audio`/cpal for `aarch64-linux-android`, enumerate devices, play a test tone) before any playback UI work, since failure reshapes Phase 5 significantly and the fallback (hand-written Oboe/AAudio JNI sink) is real new platform code.
4. **`[patch.crates-io]` git-pinned forks (egui/winit/librespot) may never have been cross-compiled to Android by their maintainers** — `cargo check --target aarch64-linux-android` succeeding today doesn't rule out the GL-resume bug class being present in an un-advanced fork commit; audit pinned commits against known upstream fixes before declaring Phase 1 done.
5. **librespot's OAuth flow assumes a desktop loopback HTTP server reachable from "a browser"** — this is unvalidated for Android's split-process browser-to-app handoff and Spotify's current redirect-URI policy disallows bare `localhost`; spike this early in Phase 4, with a custom-URI-scheme intent-filter as the realistic fallback if loopback proves unreliable.

## Implications for Roadmap

Based on research, suggested phase structure (aligned with the AND-00 through AND-10 requirements already defined in PROJECT.md):

### Phase 1: Minimal Android Build + Core Risk Spikes
**Rationale:** Packaging-tool choice and the two highest-blast-radius technical unknowns (GL resume lifecycle, cpal/AAudio Android support) must be retired before any UI or playback work is built on top of them — discovering either late forces rework across every subsequent phase.
**Delivers:** A debug APK that builds, installs, and renders a minimal egui surface on a real device, survives lock/unlock and rotation without crashing or going black, and proves `fastframe-audio`/cpal compiles and enumerates a real audio device on `aarch64-linux-android`.
**Addresses:** AND-00 (env check), AND-01 (compiles + installs), AND-02 (desktop unaffected)
**Avoids:** Pitfall 1 (GL surface/context loss on Suspended/Resumed), Pitfall 3 (cpal/AAudio Android backend gap), Pitfall 5 (packager choice — verify `cargo-apk` git HEAD vs. `cargo-apk2` vs. `cargo-ndk` live before committing), Pitfall 6 (confirm pinned fork commits are Android-aware)

### Phase 2: Strip Desktop-Only Code Paths
**Rationale:** Desktop-only modules (`milkdrop*`, `winamp*`, `mac_notch.rs`, `thumbbar.rs`, `window.rs`, `single_instance.rs`, `cast.rs`, `sonos.rs`, `zeroconf.rs`, `power.rs`, etc.) need `cfg`-gating or removal before the touch UI work in Phase 3 builds navigation around UI elements that shouldn't exist on Android, avoiding "dead paths in the interface."
**Delivers:** A build where desktop-only features are cleanly disabled on Android (no dead UI entry points), without breaking the desktop build.
**Addresses:** AND-10
**Avoids:** Technical-debt pattern of leaving non-functional code silently compiled in (e.g., `zeroconf.rs`/mDNS) without explicit disabling

### Phase 3: Touch UI Adaptation
**Rationale:** With a proven minimal build (Phase 1) and a desktop-code-free surface (Phase 2), UI work can proceed without fighting lifecycle crashes or dead navigation paths discovered mid-phase.
**Delivers:** Usable touch interface — adequate tap targets, drag-scroll, single-column narrow layout, bottom navigation, virtual keyboard handling, portrait/landscape support.
**Addresses:** AND-03 (demo mode renders), AND-04 (touch usability)
**Uses:** Existing `src/ui/` → `Action` → `app.rs` pattern, unchanged; `android-native-activity` input handling (escalate to `android-game-activity` only if touch/IME proves too limited, per STACK.md)

### Phase 4: Login & Credentials
**Rationale:** Auth must work before playback can be meaningfully tested end-to-end, and this phase has two independent unknowns (Keystore `CredentialStore` gap, OAuth loopback validity) best spiked early since both have lead time (new redirect URI registration, first-party trait implementation).
**Delivers:** Spotify Premium login on Android with Keystore-backed credential storage (never plain JSON), persisting across app restarts.
**Addresses:** AND-05
**Implements:** `src/android/credentials_android.rs` (new `keyring-core` `CredentialStore` arm), `jni_bridge.rs` Pattern 1 calls to `java.security.KeyStore`
**Avoids:** Pitfall 7 (librespot OAuth loopback not validated for Android's browser-to-app handoff) — spike this first in the phase, before building UI around it; avoid the Security Mistake of a temporary non-Keystore credential fallback

### Phase 5: Real Audio Playback
**Rationale:** With cpal/AAudio's basic Android viability already proven in Phase 1's spike, this phase focuses on correctness (play/pause/seek/queue/shuffle/repeat) and surfaces the sample-rate/format and audio-focus issues research flagged as easy to miss.
**Delivers:** Full playback controls working via librespot on-device, with native sample-rate negotiation (not hardcoded 44100 Hz) and no spurious `RECORD_AUDIO` prompts.
**Addresses:** AND-06
**Avoids:** Pitfall 4 (sample-rate/format mismatches manifesting as crackle, not errors); include a manual pause/resume/seek listening-test checklist item, not just "does audio play"

### Phase 6: Background Playback & System Media Controls
**Rationale:** This is the phase that requires the Kotlin `PlaybackService` shim and therefore depends on the Phase 1 packaging-tool decision supporting Kotlin compilation and `<service>` manifest declarations — it's the single highest-pitfall-density phase (Doze/OEM battery killers, API 34's mandatory foreground-service-type manifest attribute, audio focus, becoming-noisy handling) and must be verified on a real device, not just emulator.
**Delivers:** Playback survives screen-off/backgrounding via a foreground service with `mediaPlayback` type; lock-screen/notification/Bluetooth/headset transport controls work; audio focus duck/pause and headphone-unplug-pause both function; network loss/reconnect surfaces a "buffering" state to the system UI instead of looking frozen.
**Addresses:** AND-07, AND-08, AND-09
**Implements:** `PlaybackService` (Kotlin, Pattern 2), `src/android/service_bridge.rs` (Java→Rust), `jni_bridge.rs` additions for `MediaSession.setPlaybackState()`/notification updates (Rust→Java)
**Avoids:** Pitfall 2 (foreground service alone isn't a Doze exemption; API 34's `MissingForegroundServiceTypeException` is compile-invisible) — declare `android:foregroundServiceType="mediaPlayback"` + both FOREGROUND_SERVICE permissions from the very first commit in this phase, test 10+ minutes of real-device screen-off playback, not emulator-only

### Phase 7: Stabilization & Real-Device Hardening
**Rationale:** Research repeatedly flags "works on emulator, breaks on real device" as the dominant failure mode across GL resume, audio, and OAuth — a dedicated hardening pass against the "Looks Done But Isn't" checklist catches these before calling the port complete.
**Delivers:** Verified real-device behavior across all AND requirements: multi-minute background sessions, device reboot + re-login, rotation after genuine backgrounding (not just a quick tap-away), desktop test suite still passing.
**Addresses:** Cross-cutting verification of AND-01 through AND-10
**Avoids:** The "Looks Done But Isn't" checklist items in PITFALLS.md (API-34 foreground-service-type only checked by compiling, not by calling `startForeground()`; resume only tested with a quick tap, not a genuine multi-minute background period; desktop regressions hidden behind `cargo check` rather than `cargo test`)

### Phase Ordering Rationale

- **Risk-first ordering:** The two cheapest-to-discover-early, most expensive-to-discover-late unknowns (GL resume lifecycle, cpal/AAudio Android viability) are pulled into Phase 1 as explicit spikes rather than left implicit until Phases 3/5, per PITFALLS.md's explicit recommendation that failure here "reshapes" later phases.
- **Packaging-tool decision deliberately looks ahead to Phase 6:** ARCHITECTURE.md's Anti-Pattern 3 specifically warns against picking a packager for Phase 1's simplicity alone — the Phase 1 phase description above should include verifying Kotlin/`<service>` manifest support, not just "draws a GL surface," to avoid a disruptive mid-project packaging migration.
- **Desktop-code stripping (Phase 2) before touch UI (Phase 3):** avoids building new navigation around UI elements that will need to be removed anyway, and keeps AND-10 from becoming an afterthought cleanup pass.
- **Credentials (Phase 4) before full playback (Phase 5):** login must work before playback can be meaningfully end-to-end tested, and both of Phase 4's unknowns (Keystore trait gap, OAuth loopback validity) have real lead time if they require new code or a new Spotify redirect URI registration.
- **Background/MediaSession (Phase 6) last among functional phases:** it's the only phase requiring the Kotlin shim and has the highest pitfall density (3 of 5 critical pitfalls concentrate here or depend on earlier phases being correct first) — building it last means the Rust-side command channel (`PlayerCommand::Play/Pause/etc.`) already exists and stable from Phase 5, so Phase 6 only adds JNI plumbing, not new playback logic.
- **Stabilization (Phase 7) as an explicit phase, not implicit "done":** research's own "Looks Done But Isn't" checklist is long enough (5 items, each a real-device-only distinction) to warrant a dedicated verification pass rather than assuming each feature phase's own testing already covered it.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 1:** Live re-verification of packaging-tool maintenance status (`cargo-apk` vs. `cargo-apk2` vs. `cargo-ndk` vs. `xbuild`) at decision time — STACK.md and PITFALLS.md both flag this as a fast-moving target where even this research's own confidence is MEDIUM; also needs hands-on verification of whether the chosen tool can compile Kotlin and declare `<service>` manifest entries (Phase 6 dependency).
- **Phase 4:** OAuth loopback-vs-custom-scheme decision needs on-device validation before implementation, not just research — LOW confidence in PITFALLS.md pending direct testing; and the `keyring-core`/`android-keyring` trait-family gap needs a fresh check (ARCHITECTURE.md flags this as possibly resolved by the time Phase 4 starts).
- **Phase 6:** Platform `MediaSession` vs. `androidx.media3.session.MediaSessionService` is an explicit judgment call ARCHITECTURE.md says must be made at the start of the phase, not mid-phase, since it determines whether Gradle/Maven dependencies become necessary; also re-verify Android 15+ `AudioManager.requestAudioFocus()` behavior-change reports (currently LOW confidence/unverified against an official changelog) if the target device runs API 35+.

Phases with standard patterns (skip research-phase):
- **Phase 3 (touch UI):** Standard egui/winit touch-input patterns, no Android-specific unknowns beyond input-handling feature choice already resolved in STACK.md.
- **Phase 5 (playback correctness):** Once Phase 1's cpal spike is resolved, the remaining work (sample-rate negotiation, focus-state wiring) follows documented AAudio/cpal patterns in PITFALLS.md directly.
- **Phase 7 (stabilization):** Execution against an already-known checklist (PITFALLS.md's "Looks Done But Isn't" section), not new research.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM-HIGH | Core windowing/packaging findings verified against upstream `emilk/egui` repo, crates.io, and GitHub API metadata (commit dates, repo archive status). Phase 6 JNI/Kotlin tooling specifics (`cargo-apk2`, `cargo-ndk`) are MEDIUM — smaller, less-verified projects, no hands-on build performed. |
| Features | MEDIUM-HIGH | Official Android/Media3 docs (developer.android.com) confirm the platform contract (foreground service, MediaSession, audio focus) with HIGH confidence. Rust/egui-specific JNI integration details are MEDIUM/LOW since no official egui-on-Android media guide exists. |
| Architecture | MEDIUM | Core JNI/context patterns (`ndk-context`, `jni` crate usage) are HIGH confidence from official `docs.rs` sources. Service/MediaSession wiring and the exact shape of the Kotlin shim are synthesized from verified primitives, not copied from one proven reference project combining this exact stack — treat as a sound design, not a battle-tested one. |
| Pitfalls | MEDIUM | Mix of verified GitHub issues/official docs (GL resume crash, API 34 foreground-service-type requirement — HIGH confidence) and WebSearch-corroborated community reports (OEM battery killers, Android 15 audio-focus changes — LOW-MEDIUM confidence). cpal/AAudio specifics and librespot-OAuth-on-Android are explicitly flagged LOW confidence pending on-device validation. |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- **cpal 0.18's actual Android/AAudio support is unverified** — no source confirms it works for this exact version; treat as an open question requiring a Phase 1 spike, with a hand-written Oboe/AAudio JNI sink as the budgeted fallback if it fails.
- **`keyring-core` has no ready-made Android `CredentialStore` provider** — the one maintained Android-Keystore crate (`android-keyring`) targets an incompatible trait family (the older `keyring` crate, not `keyring-core`); Phase 4 should budget for writing this first-party, using `android-keyring` only as a JNI-call reference. Re-check both crates' latest versions at Phase 4 start in case this gap has closed.
- **librespot's OAuth loopback flow has not been validated against Android's browser-to-app handoff model**, and Spotify's current redirect-URI policy may not accept the project's existing registered URI unchanged — needs an early, dedicated Phase 4 spike with a custom-URI-scheme fallback plan.
- **Packaging-tool live maintenance status can shift quickly** (the `cargo-apk`→`xbuild` docs.rs deprecation note is already stale/wrong as of this research) — re-verify `cargo-apk`, `cargo-apk2`, and `cargo-ndk` repo activity directly on GitHub at Phase 1 decision time rather than trusting this document's snapshot.
- **Android 15+ (API 35+) `AudioManager` focus-handling changes** are WebSearch-sourced and unverified against an official changelog — only relevant if the dev device/emulator runs API 35+; flagged for a Phase 6 spike if applicable.
- **OEM-specific battery-optimization killing foreground services** (Samsung/Xiaomi/etc.) is a known, unfixable-in-app Android ecosystem issue — not a gap to resolve, but should be documented as a known limitation rather than built around defensively.

## Sources

### Primary (HIGH confidence)
- `docs.rs/crate/eframe/0.36.2/features` — eframe 0.36.2's native Android feature set
- `github.com/emilk/egui` `examples/hello_android` (current `main`, PR #8122) — canonical upstream Android build recipe
- `github.com/emilk/egui` issues #3674/#3861, fix PR #3847 — GL resume crash root cause and fix
- `docs.rs/android-activity`, `docs.rs/ndk-context` — entry-point model, JavaVM/Context retrieval mechanics
- `developer.android.com/media/media3/session/background-playback`, `/about/versions/14/changes/fgs-types-required`, `/reference/android/media/AudioFocusRequest`, `/reference/androidx/media3/session/MediaStyleNotificationHelper.MediaStyle` — official foreground-service, MediaSession, and audio-focus contracts
- `github.com/rust-mobile/xbuild` (via `gh api`) — repo self-description confirms "(unmaintained)", contradicting its docs.rs-promoted status as cargo-apk's successor
- `github.com/rust-mobile/cargo-apk` + `cargo-subcommand` issue #29 (via `gh api`) — confirms active maintenance, bug-fix timeline

### Secondary (MEDIUM confidence)
- `github.com/bbqsrc/cargo-ndk`, `github.com/mzdk100/cargo-apk2` READMEs — Kotlin/manifest capability claims, not hands-on verified
- `docs.rs/android-keyring`, `docs.rs/keyring-core` — confirms the trait-family incompatibility gap for Android credential storage
- Tauri v2 Mobile Plugin docs (`v2.tauri.app`) — independent confirmation of the `external fun`/`Java_<pkg>_<Class>_<method>` JNI convention, used as architectural precedent not literal template
- `wz-phone` project source, Titanium SDK JIRA AC-6117, AOSP/WebRTC AAudio source — real-world precedent for Oboe/AAudio-via-JNI fallback and Doze-related playback throttling patterns
- `github.com/crmne/winit`, `github.com/crmne/egui` (via `gh api`) — confirmed clean, non-divergent forks (checked last 8 commits only)

### Tertiary (LOW confidence)
- WebSearch reports of Android 15 `AudioManager.requestAudioFocus()` behavior changes — unverified against an official changelog, flagged for a Phase 6 spike
- `docs.rs/librespot-oauth` loopback-flow description — no explicit mobile guidance; Android applicability inferred, not confirmed
- `dontkillmyapp.com`-style OEM battery-killer community reports — anecdotal but consistent across multiple independent threads

---
*Research completed: 2026-10-14*
*Ready for roadmap: yes*

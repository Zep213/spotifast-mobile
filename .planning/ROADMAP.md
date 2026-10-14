# Roadmap: Spotifast Android

## Overview

Port spotifast (Rust + egui desktop Spotify client) to Android while keeping Rust/egui unchanged and never breaking the desktop build. The journey starts by retiring the two highest-blast-radius unknowns — packaging tool choice, GL-surface lifecycle, and cpal/AAudio viability — in a minimal spike build (Phase 1), then strips desktop-only code before building touch UI on a clean surface (Phases 2-3), then layers in login/credentials, real playback, and background/system-media integration in dependency order (Phases 4-6), and closes with a dedicated real-device stabilization pass (Phase 7) since "works on emulator, breaks on real device" is the dominant failure mode this domain exhibits. Every phase ends with `cargo check` green on the desktop Linux target — non-negotiable per PROJECT.md.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Minimal Android Build + Core Risk Spikes** - A debug APK builds, installs, renders, and survives lock/rotate; packaging tool and audio backend risk retired
- [ ] **Phase 2: Strip Desktop-Only Code Paths** - Desktop-only modules cfg-gated out of Android with no dead UI entry points
- [ ] **Phase 3: Touch UI Adaptation** - Full demo-mode UI usable with touch, in portrait and landscape
- [ ] **Phase 4: Login & Credentials** - Spotify Premium login on Android with Keystore-backed credential storage
- [ ] **Phase 5: Real Audio Playback** - Full playback controls (play/pause/seek/queue/shuffle/repeat) working via librespot on-device
- [ ] **Phase 6: Background Playback & System Media Controls** - Playback survives backgrounding; lock-screen/notification/headset controls work
- [ ] **Phase 7: Stabilization & Real-Device Hardening** - Cross-cutting verification of AND-01 through AND-09 on a real device

## Phase Details

### Phase 1: Minimal Android Build + Core Risk Spikes
**Goal**: A debug APK builds, installs, and renders a minimal egui surface on a real device/emulator, and the two highest-blast-radius technical unknowns (GL-surface resume lifecycle, cpal/AAudio Android viability) are retired before any UI or playback work depends on them.
**Depends on**: Nothing (first phase — manual environment setup already completed 2026-10-14: Rust 1.98.0 + Android targets, SDK platform android-34, NDK 27.0.12077973)
**Requirements**: AND-00, AND-01, AND-02
**Success Criteria** (what must be TRUE):
  1. `scripts/check-android-env.sh` exits 0 with no `[FAIL]` lines
  2. Packaging tool is chosen (cargo-apk git HEAD, cargo-apk2, or cargo-ndk+Gradle, verified live against Phase 6's Kotlin/`<service>` manifest needs) and `cargo check --target aarch64-linux-android` succeeds, producing an installable debug APK
  3. APK installs on a real device or emulator and renders a minimal egui surface
  4. App survives screen lock/unlock and rotation without crashing or going black (confirms pinned `crmne/egui`/`crmne/winit` fork commits are downstream of the GL-resume fix)
  5. `fastframe-audio`/cpal compiles for `aarch64-linux-android` and enumerates a real audio device (plays a test tone)
  6. `cargo check` on the desktop Linux target still passes, existing tests still pass
**Plans**: 4 plans

Plans:
- [ ] 01-01-PLAN.md — Install cargo-apk (D-01), pass env check (AND-00), D-06 fork audit (PR #3867), desktop gate script + pre-change baseline
- [ ] 01-02-PLAN.md — Remove Android compile blockers (rfd, eframe accesskit, credential store arm), add android_main + package metadata, build debug APK, desktop gate
- [ ] 01-03-PLAN.md — Local x86_64 AVD, install + render proof, cpal/AAudio spike (D-05, stop-on-failure)
- [ ] 01-04-PLAN.md — GL-resume lifecycle spike (D-04) automated + human check, final phase gates

### Phase 2: Strip Desktop-Only Code Paths
**Goal**: Desktop-only modules are cleanly disabled on Android behind `cfg(target_os = "android")` before touch UI work builds navigation around them, so no dead paths exist in the Android interface.
**Depends on**: Phase 1
**Requirements**: AND-10
**Success Criteria** (what must be TRUE):
  1. Desktop-only modules (`milkdrop*`, `winamp*`, `ui/winamp/`, `mac_notch.rs`, `notch.rs`, `thumbbar.rs`, `window.rs`, `single_instance.rs`, `opener.rs`, `cast.rs`, `sonos.rs`, `zeroconf.rs`, `appearance.rs`, `power.rs`) are excluded from the Android build via `cfg` gating, not copied or duplicated
  2. No menu items, settings, or buttons referencing a disabled feature are reachable in the Android UI
  3. `cargo check --target aarch64-linux-android` succeeds with desktop-only code excluded, APK still installs and renders
  4. `cargo check` on the desktop Linux target still passes, existing tests still pass
**Plans**: TBD

### Phase 3: Touch UI Adaptation
**Goal**: The full demo-mode interface is usable with touch on a real device, in both orientations, without a Spotify account.
**Depends on**: Phase 2
**Requirements**: AND-03, AND-04
**Success Criteria** (what must be TRUE):
  1. App opens on Android in `--demo` mode without an account and shows Home, Library, Search, Queue, and the player bar
  2. Touch targets meet an adequate minimum size (~44dp), and drag-scroll works throughout the app
  3. Layout collapses to a single column on narrow screens with bottom navigation replacing the desktop sidebar
  4. Virtual keyboard appears for text input fields (e.g. Search) without obscuring them
  5. UI remains usable and correctly laid out in both portrait and landscape
  6. `cargo check` on the desktop Linux target still passes, existing tests still pass
**Plans**: TBD
**UI hint**: yes

### Phase 4: Login & Credentials
**Goal**: A user can log in with their Spotify Premium account on Android, with the credential stored in platform-secure storage and never in plain JSON.
**Depends on**: Phase 3
**Requirements**: AND-05
**Success Criteria** (what must be TRUE):
  1. User can complete Spotify Premium OAuth login end-to-end on a real Android device (loopback flow validated, or custom-URI-scheme fallback implemented if loopback proves unreliable)
  2. Credential is stored via a new `keyring-core` `CredentialStore` arm backed by Android Keystore (`java.security.KeyStore`, "AndroidKeyStore" provider) — never plain JSON
  3. Closing and reopening the app keeps the user logged in (credential persists across restarts)
  4. No credential appears in logs or in any plain-text state file
  5. `cargo check` on the desktop Linux target still passes, existing tests still pass
**Plans**: TBD

### Phase 5: Real Audio Playback
**Goal**: Full playback controls work end-to-end via librespot on real Android device audio output.
**Depends on**: Phase 4
**Requirements**: AND-06
**Success Criteria** (what must be TRUE):
  1. User can play, pause, skip forward, skip back, and seek within a track on a real device
  2. Volume control, queue, shuffle, and repeat all function correctly
  3. Audio negotiates the device's native sample rate (not hardcoded 44100 Hz) and plays without crackle or artifacts across pause/resume/seek
  4. No spurious `RECORD_AUDIO` permission prompt appears
  5. `cargo check` on the desktop Linux target still passes, existing tests still pass
**Plans**: TBD

### Phase 6: Background Playback & System Media Controls
**Goal**: Playback survives screen-off and backgrounding via a foreground service, and system media controls (lock screen, notification, headset) control the app.
**Depends on**: Phase 5
**Requirements**: AND-07, AND-08, AND-09
**Success Criteria** (what must be TRUE):
  1. Music continues playing for 10+ minutes with the screen off or the app backgrounded, via a foreground service declaring `android:foregroundServiceType="mediaPlayback"` and the matching permission, with a visible notification
  2. Lock-screen, notification (`MediaSession`/MediaStyle), and headset/Bluetooth transport controls (play/pause/skip) send commands back to the app and reflect current playback state
  3. Audio focus loss (e.g. simulated call) ducks or pauses playback correctly, and unplugging headphones pauses playback (`ACTION_AUDIO_BECOMING_NOISY`)
  4. Network loss and reconnect during playback surface a "buffering" state to the system UI instead of appearing frozen or crashing
  5. `cargo check` on the desktop Linux target still passes, existing tests still pass
**Plans**: TBD

### Phase 7: Stabilization & Real-Device Hardening
**Goal**: The full port is verified end-to-end on a real device against the "works on emulator, breaks on real device" failure class, and the desktop build remains fully intact.
**Depends on**: Phase 6
**Requirements**: Cross-cutting verification of AND-01 through AND-09 (no new requirement — see REQUIREMENTS.md traceability note)
**Success Criteria** (what must be TRUE):
  1. Real-device checklist passes: multi-minute (10+ min) background session, device reboot followed by re-login, rotation after a genuine multi-minute background period (not just a quick tap-away)
  2. `startForeground()` with `mediaPlayback` type is confirmed to succeed at runtime on the target device, not just compile
  3. Desktop test suite passes via `cargo test` (not only `cargo check`), confirming no hidden regressions
  4. README documents Android build/run instructions (packaging tool, env check script, how to sideload)
  5. `cargo check` on the desktop Linux target still passes
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5 → 6 → 7

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Minimal Android Build + Core Risk Spikes | 0/4 | Planned | - |
| 2. Strip Desktop-Only Code Paths | 0/TBD | Not started | - |
| 3. Touch UI Adaptation | 0/TBD | Not started | - |
| 4. Login & Credentials | 0/TBD | Not started | - |
| 5. Real Audio Playback | 0/TBD | Not started | - |
| 6. Background Playback & System Media Controls | 0/TBD | Not started | - |
| 7. Stabilization & Real-Device Hardening | 0/TBD | Not started | - |

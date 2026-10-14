# Feature Research

**Domain:** Android platform integration for a streaming music player (Rust + egui port of spotifast)
**Researched:** 2026-10-14
**Confidence:** MEDIUM-HIGH (official Android/Media3 docs confirm the platform contract; Rust/egui-specific JNI integration details are MEDIUM/LOW since no official egui-on-Android media guide exists — verify against the actual android-activity/eframe version during Phase 1/6 implementation)

## Scope Note

This research is scoped to **Android platform capabilities**, not Spotify features (those already exist via librespot on desktop). It answers: what does a background music player need to *feel like a real Android app* versus what is purely a Play Store compliance cost that a personal, never-published debug APK can skip.

The app is **streaming-only by design** (no offline download/cache — see PROJECT.md constraint and AGENTS.md). This has one concrete implication, addressed inline below: Android's MediaSession/foreground-service model does **not** assume downloadable content — it works identically for pure-streaming apps (see "Streaming-only implications" note under Table Stakes).

---

## Feature Landscape

### Table Stakes (Users Expect These)

These are the minimum for the app to function as a background music player at all — without them the app isn't "basic but working," it's broken (audio stops when screen locks, no lock-screen controls, blasts through speaker on headphone unplug, etc.). All of these map to PRD requirements AND-07, AND-08, AND-09 and PRD Fase 6.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Foreground Service with `mediaPlayback` type | Without it, Android kills the process within seconds of the screen going off or the app backgrounding. This is the #1 reason "music stops when I lock my phone" bugs happen. | HIGH | Requires a minimal Kotlin/Java `Service` subclass declared in `AndroidManifest.xml` with `android:foregroundServiceType="mediaPlayback"`, started via JNI from Rust (the `android-activity`/NDK layer has no native API for this — it's Java-framework-only). Needs `FOREGROUND_SERVICE` permission always, plus `FOREGROUND_SERVICE_MEDIA_PLAYBACK` if targeting API 34+. Maps to PRD R7 ("menor código nativo possível" — this is the feature that forces that minimal Kotlin shim to exist at all). |
| `POST_NOTIFICATIONS` runtime permission request (Android 13+/API 33+) | Foreground service requires a visible notification within ~5s of `startForeground()`. On API 33+, if the user hasn't granted notification permission, the notification silently won't display — the service still runs but the user sees no lock-screen/shade controls, which looks broken. | MEDIUM | One-time runtime permission dialog, triggered from the Kotlin shim before/at first playback. Small JNI call surface. |
| MediaStyle notification (transport controls + album art) | This is the only way to get play/pause/skip controls in the notification shade and on the lock screen on modern Android — there is no other supported surface. | HIGH | Built via `androidx.media3.session.MediaStyleNotificationHelper.MediaStyle` (or the raw `android.app.Notification.MediaStyle`), bound to the app's `MediaSession` token. Depends on **both** the foreground service (to host/post it) and MediaSession (to supply the token) existing first. |
| `MediaSession` (lock-screen/Bluetooth/headset transport controls, metadata, playback state) | Lock-screen media widget, Bluetooth headset play/pause/skip buttons, wired-headset remote buttons, Android's "Now Playing" system card, and voice assistant "pause/skip" commands all route through `MediaSession`, not through the app's own UI. Without it the app can only be controlled while its own screen is in the foreground. | HIGH | Java-framework API (`android.media.session.MediaSession` or `androidx.media3.session.MediaSession`), no NDK equivalent — same JNI shim as the foreground service. Should map Spotify Connect state from `src/player.rs`/`src/backend.rs` into `PlaybackState`/`MediaMetadata` objects. This is also the single integration point that Android Auto (if ever wanted) would build on top of — see Differentiators. |
| Audio focus handling (request on play, abandon on stop, duck/pause on transient loss, pause on permanent loss) | Without this, the app's audio overlaps a phone call ringtone, a nav-app voice prompt, or another music app — a glaring, obviously-broken behavior on Android specifically (iOS/desktop users don't expect this interaction at all). | MEDIUM-HIGH | `AudioManager.requestAudioFocus()`/`AudioFocusRequest` (API 26+) is a Java-only API; `cpal`'s AAudio backend does **not** handle this — it only owns the audio stream, not focus arbitration. Needs a JNI call independent of the audio data path. Since this is music (not speech), do **not** set `CONTENT_TYPE_SPEECH` — let the system auto-duck on transient-can-duck losses per the API 26+ default, and pause outright on permanent loss (another player started) or transient-no-duck loss (e.g., voice assistant). |
| `ACTION_AUDIO_BECOMING_NOISY` handling (headphone/Bluetooth unplug → pause) | When headphones are unplugged or a Bluetooth device disconnects mid-playback, Android is about to reroute audio to the loud internal speaker. Every real media app pauses on this broadcast; failing to do so is one of the most-cited "this app isn't finished" bugs in Android media app reviews. | LOW-MEDIUM | Register a `BroadcastReceiver` (via the Kotlin shim or dynamically through JNI) and call into `player.rs` to pause. Independent of MediaSession but should update MediaSession's `PlaybackState` to reflect the pause. |
| Audio output route change handling (Bluetooth connect mid-session, wired headset insert) | Spotify-class apps are expected to keep playing (not restart/glitch) when a Bluetooth speaker connects or a headset is plugged in while already playing. | LOW | Mostly follows from `cpal`/AAudio's own device-change handling plus the becoming-noisy receiver above; verify `fastframe-audio`/`sink.rs` reconnects cleanly to a new output device without an audible glitch. |
| Network loss/reconnect + buffering/retry handling | Because this app is **streaming-only with no offline fallback**, a dropped network connection is the single biggest threat to perceived reliability — there is no cached audio to fall back on. This elevates AND-09 above "nice lifecycle handling" to genuinely table-stakes: users expect brief network drops (elevator, subway, wifi↔cellular handoff) to resume automatically, not kill playback outright. | MEDIUM | Lives in `src/backend.rs`/`src/player.rs`, not JNI — detect `librespot` connection loss, retry with backoff, surface a "buffering/reconnecting" state to both the UI and the MediaSession `PlaybackState` (so lock-screen controls don't look frozen or wrong). |
| Surviving normal backgrounding without killing the process | Screen off, app backgrounded via home button, multitasking to another app — the process must stay alive and playing. This is the baseline case the foreground service exists to solve. | Covered by Foreground Service above | Note the ceiling: a correctly-implemented foreground service is exempt from Doze's process-kill behavior while actively running, but it is **not** a guarantee against OEM-specific aggressive battery managers (MIUI/Xiaomi, Huawei, some Samsung/OnePlus skins) that kill foreground services outside stock AOSP Doze rules. This is a known, unfixable-in-app Android ecosystem pitfall — worth a one-line README note ("if playback stops in background, check battery optimization/auto-start settings for this app"), not worth building a defensive feature for in a personal project. Flagged for PITFALLS research. |

**Streaming-only implication (explicit answer to the research question):** Android's `MediaSession` and foreground-service (`mediaPlayback`) model make **no assumption about where the audio bytes come from** — they're purely a session/metadata/transport-state contract between the app and the OS. Internet-radio apps, podcast-streaming apps (without download), and Spotify's own free/streaming-only tier all use exactly this same model. The only place "downloadable content" leaks into the platform contract is Android Auto/Automotive's `MediaBrowser` content tree, which expects a browsable item hierarchy (artists/albums/playlists) with metadata and artwork — but that tree can be populated from live API calls just as easily as from a local cache, so it's not actually offline-dependent either. **No table-stakes feature here is blocked or complicated by the no-download constraint.** The one place the constraint *does* raise the bar is the network-loss/retry row above — without a cache to fall back on, reconnect robustness matters more than it would for a download-capable app.

### Differentiators (Competitive Advantage)

Legitimate platform features real Spotify-class apps have, but explicitly **not needed** for a personal, single-user, never-published study APK. Documented so the roadmap can consciously defer them rather than silently forget them.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Android Auto / Android Automotive OS support | Lets the app be controlled from a car head unit. | HIGH | Requires implementing `MediaLibraryService`/`MediaBrowserServiceCompat` with a browsable content tree (artists/playlists/albums as `MediaItem`s), built on top of the MediaSession work above. Google's official design requirements and Play listing review only apply to apps distributed through Play — a sideloaded debug build can technically still be tested against Android Auto's desktop head unit simulator or via the "Unknown sources" developer toggle, but it's meaningful extra work (content-tree mapping from Spotify's catalog) for a feature with no listed-store audience. Skip. |
| Home-screen widget (now-playing + transport controls) | Quick glanceable control without opening the app. | MEDIUM-HIGH | Needs a separate `AppWidgetProvider`/`RemoteViews` (Kotlin), its own update loop driven by MediaSession callbacks, and `PendingIntent`s wired back into the Rust playback engine. Entirely additive, no dependency from table-stakes features. Skip. |
| Adaptive icon / Material You themed (monochrome) icon | Matches modern Android launcher icon theming. | LOW | Pure resource/XML work (adaptive icon layers, `<monochrome>` icon variant), no Rust/JNI involvement. Cosmetic only. Skip, or do in 10 minutes if bored. |
| Predictive back gesture support | Smooth "peek home" animation on the system back gesture at the nav root. | LOW-MEDIUM | Mostly matters for multi-Activity apps; this project is effectively single-Activity (egui owns in-app navigation, back button handled inside egui's own nav stack per the architecture notes). The only system-level win is the exit-to-launcher animation, via `android:enableOnBackInvokedCallback="true"` in the manifest plus wiring `OnBackInvokedCallback` in the Kotlin shim instead of relying on the legacy `onBackPressed()` path. Starting with apps targeting Android 16/API 36, this is close to mandatory to avoid an opt-out warning, but that only matters if ever targeting/publishing against API 36 — for a personal debug build at whatever API level is convenient, skip. |
| Edge-to-edge display (drawing under status/nav bars with inset-aware padding) | Modern look; mandatory **only** for apps that *target* API 35+ when distributed, with the opt-out fully removed at API 36. | LOW-MEDIUM | Distinct from the touch-safe-area work already planned in PRD Fase 3 (notch/gesture-bar margins) — that's a correctness requirement for usability on notched/gesture-nav devices regardless of edge-to-edge; true edge-to-edge (drawing content behind the system bars for a borderless look) is a visual differentiator layered on top. Nice-to-have polish, not required to avoid a "broken" feel. Low priority. |
| Splash screen (Android 12+ `SplashScreen` API) | Consistent branded launch animation instead of a blank/default white flash. | LOW | Purely cosmetic manifest/theme work. Skip. |
| App Actions / Assistant voice integration ("Hey Google, play X on Spotifast") | Voice-driven playback outside the app. | HIGH | Requires `shortcuts.xml`/App Actions capability declarations layered on the MediaBrowser tree from the Android Auto work above. Not worth it without a listed, discoverable app. Skip. |
| Picture-in-Picture | N/A for an audio-only app (no video surface to shrink). | — | Not applicable to this domain at all — omit from consideration entirely, not even a "skip." |

### Anti-Features (Store-Compliance-Only — Deliberately Not Needed)

These exist in "how to ship a real Spotify-class app" checklists, but every one of them is a **Google Play distribution requirement**, not an Android *platform* requirement. Since this APK is sideloaded, debug-signed, and never published, none of these apply. Listing them explicitly prevents scope creep from generic "production Android app" checklists bleeding into a personal study project.

| Feature | Why It's On Generic Checklists | Why Not Needed Here | Alternative |
|---------|-------------------------------|----------------------|-------------|
| Target API level compliance deadlines (Play's "must target API N-1 within X months" policy) | Google enforces a rolling target-SDK floor to keep the Play Store catalog current/secure. | This policy is enforced at Play Store *upload/update* time, not by the OS at install/runtime. A sideloaded APK runs fine on any device regardless of its `targetSdkVersion`, forever. | Pick whatever `targetSdkVersion`/`compileSdkVersion` matches the installed SDK platform (android-34 per the environment check) and matches what the packaging tool (cargo-apk2/xbuild/cargo-ndk) supports well; don't chase the latest API level for its own sake. |
| Play Integrity API / SafetyNet attestation | Lets a backend verify the app binary and device aren't tampered with / rooted, used to gate licensed content or detect cheating. | No backend exists (project has no hosted service, per AGENTS.md), and there's no licensing enforcement beyond what librespot/Spotify's own servers already do. | Nothing — not applicable even conceptually. |
| In-app review prompts (Play Core Review API) | Nudges users to rate the app on Play. | Only functions for apps installed via the Play Store; on a sideloaded build the API silently no-ops. | Nothing — not applicable. |
| Android App Bundle (`.aab`) / Play Feature Delivery / dynamic feature modules | Play-only distribution format for optimized, per-device APK splits. | A plain multi/single-ABI debug `.apk` installs directly via `adb install`; `.aab` only matters for Play's dynamic delivery pipeline. | Build a standard debug APK for `aarch64-linux-android` (device) / `x86_64-linux-android` (emulator), per PRD section 3. |
| Play Console metadata (Data Safety form, target-audience declaration, ads SDK transparency) | Store-listing compliance paperwork Google requires before publishing. | There is no store listing. | Nothing — not applicable. |
| Google Play App Signing | Lets Google manage/rotate the app's release signing key. | No release build, no upload to Play; the debug keystore is sufficient for a personal device/emulator install. | Use the default debug keystore cargo-apk2/xbuild/cargo-ndk generates. |
| Crash reporting / analytics / telemetry SDKs (Firebase Crashlytics, Analytics, etc.) | Standard production observability expected by most "real app" checklists. | Explicitly forbidden by the project's own `AGENTS.md` ("sem telemetria"), and unnecessary for a single-developer debug build — `adb logcat` and local panic logs are sufficient. | `adb logcat`, Rust panic hooks writing to a local log file (already implied by PRD Fase 7 "logs de bug report"). |
| Accessibility (TalkBack) full compliance audit | Play policy and app-quality guidelines increasingly expect baseline screen-reader support. | No audit/store gate applies to a personal sideloaded build, and this is a single-user (the developer's) app. | Not required to be fully compliant; fine to leave as a known gap rather than investing phase time in it. |
| In-app billing / Play Billing integration | N/A — generic checklist item for apps that sell anything. | Spotifast doesn't sell anything; subscription is handled entirely by the user's existing Spotify Premium account outside this app. | Nothing — not applicable. |
| ProGuard/R8 obfuscation, APK size optimization for Play's size limits | Store quality bars (download size, code shrinking) for a public catalog listing. | No size constraint applies to a locally-installed debug APK; R8/ProGuard are Kotlin/Java-side concerns anyway and this is a Rust-native app with only a thin Kotlin shim. | Leave default debug build settings; revisit only if local APK size becomes genuinely inconvenient to `adb install` repeatedly (unlikely). |
| Android Auto / Automotive OS Play design-requirement review | Google gates car-category Play listings behind a UI design review. | Covered under Differentiators above as "skip the feature entirely," but worth repeating here: even *if* Android Auto support were built, the Play design review specifically (not the technical integration) is 100% a store-only cost that doesn't apply to a sideloaded/dev-mode test. | N/A — moot since the feature itself is deferred. |

## Feature Dependencies

```
Foreground Service (mediaPlayback type)
    └──requires──> Kotlin/Java Service shim + JNI bridge from Rust
    └──requires──> POST_NOTIFICATIONS runtime permission (API 33+)
    └──requires──> MediaStyle Notification (must post one within ~5s of startForeground)
                       └──requires──> MediaSession (supplies the session token + metadata)

MediaSession
    └──requires──> same Kotlin/Java shim + JNI bridge (shared JNI boundary with Foreground Service)
    └──enables──> Lock-screen controls, Bluetooth/headset hardware buttons, voice "pause/skip"
    └──is prerequisite for──> Android Auto / MediaBrowser tree (differentiator, deferred)
    └──is prerequisite for──> Home-screen widget now-playing data (differentiator, deferred)

Audio Focus handling
    └──independent of Foreground Service/MediaSession (separate JNI call into AudioManager)
    └──should update──> MediaSession PlaybackState (so lock screen reflects duck/pause correctly)

ACTION_AUDIO_BECOMING_NOISY handling
    └──independent JNI/BroadcastReceiver registration
    └──should update──> MediaSession PlaybackState (same reason as above)

Network loss/reconnect handling
    └──lives in src/backend.rs + src/player.rs (no JNI)
    └──should update──> MediaSession PlaybackState ("buffering"/"error" states)
    └──elevated priority because──> no offline cache exists to fall back on (project constraint)

Android Auto (differentiator)
    └──requires──> MediaSession (above) + new MediaBrowserService/MediaLibraryService content tree
    └──conflicts with──> "no new Kotlin/Gradle surface" minimization goal from PRD R7 (adds more JNI-exposed classes)

Edge-to-edge display / Predictive back (differentiators)
    └──independent of all media features; pure UI-shell/manifest work
    └──overlaps with but is distinct from PRD Fase 3's notch/gesture-bar safe-area work (that's correctness, this is polish)
```

### Dependency Notes

- **Everything JNI-related funnels through one shim boundary.** Foreground Service, MediaSession, audio focus, `POST_NOTIFICATIONS`, and the becoming-noisy receiver all require calling into Android's Java framework APIs that have no NDK/native equivalent. Per PRD R7's own framing ("definir o menor código nativo possível e isolá-lo"), these should be implemented as **one minimal Kotlin shim class** (or a small set of them) rather than scattered JNI call sites — this is the single most consequential architectural decision for Phase 6, and it also constrains the Phase 1 packaging choice (a pure `cargo-apk`-style NativeActivity build with zero Kotlin becomes impossible once this shim exists; the project will need at least a minimal Gradle-buildable module even if the bulk of the app stays Rust/NDK-only).
- **MediaStyle Notification requires MediaSession, not the other way around.** Build the session first, then construct the notification style from its token — attempting the reverse order is a common implementation mistake in native/cross-platform media app ports.
- **Audio focus and becoming-noisy handling are decoupled from the foreground-service/MediaSession pair** but should both feed state back into MediaSession's `PlaybackState` so lock-screen/Bluetooth UI never shows a stale "playing" indicator while the app has actually paused itself.
- **Network-loss handling has no JNI dependency** — it's pure `src/backend.rs`/`src/player.rs` work — but its *priority* is elevated specifically because of the no-offline-cache constraint, making it effectively table-stakes rather than ordinary lifecycle polish.
- **Android Auto and the widget both build on top of MediaSession**, so if either is ever revisited post-MVP, MediaSession must already be correct and complete first — don't attempt them in parallel with the initial MediaSession implementation.

## MVP Definition

Framed against the PRD's own phases (Fase 5 = audio/playback, Fase 6 = background + media controls) rather than a generic v1/v1.x/v2 split, since the roadmap is already phase-structured.

### Launch With (Fase 6 — background + media controls)

- [ ] Foreground Service (`mediaPlayback` type) + `POST_NOTIFICATIONS` permission request — without this, playback dies the instant the screen locks (AND-07)
- [ ] MediaSession + MediaStyle notification with transport controls and metadata/art — this is the entire point of AND-08 (lock screen, notification, headset commands)
- [ ] Audio focus request/abandon + duck-or-pause behavior — avoids the single most jarring cross-app audio bug (AND-09)
- [ ] `ACTION_AUDIO_BECOMING_NOISY` → pause — avoids the "blasted through speaker" bug (AND-09)
- [ ] Network loss/reconnect handling with buffering state surfaced to MediaSession — required precisely *because* there's no offline fallback (AND-09)

### Add After Validation (if the project continues past the study milestone)

- [ ] Home-screen widget — once MediaSession is solid and the developer actually wants glanceable control
- [ ] Predictive back / edge-to-edge polish — once the touch UI (Fase 3) has stabilized and there's appetite for visual polish
- [ ] Adaptive/themed icon — trivial, do whenever

### Future Consideration (explicitly out of scope for this milestone, revisit only if the project ever moves toward real distribution)

- [ ] Android Auto / Automotive OS support — meaningful new surface (MediaBrowser tree) with no audience until/unless this ever becomes a published app
- [ ] App Actions / Assistant voice integration — same reasoning, depends on Android Auto's content tree work
- [ ] Any Play Store compliance item from the Anti-Features table — by definition, only relevant if the "never published" constraint in PROJECT.md ever changes

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|----------------------|----------|
| Foreground Service (mediaPlayback) | HIGH | HIGH (JNI shim) | P1 |
| POST_NOTIFICATIONS permission flow | HIGH | LOW | P1 |
| MediaSession | HIGH | HIGH (JNI shim) | P1 |
| MediaStyle notification | HIGH | MEDIUM (builds on above) | P1 |
| Audio focus handling | HIGH | MEDIUM | P1 |
| Becoming-noisy (headphone unplug) handling | HIGH | LOW | P1 |
| Network loss/reconnect + buffering state | HIGH | MEDIUM | P1 |
| Audio output route change handling | MEDIUM | LOW | P2 |
| Home-screen widget | MEDIUM | MEDIUM-HIGH | P3 |
| Android Auto support | LOW (no real audience) | HIGH | P3 |
| Adaptive/themed icon | LOW | LOW | P3 |
| Predictive back gesture | LOW | LOW-MEDIUM | P3 |
| Edge-to-edge display | LOW | LOW-MEDIUM | P3 |
| Splash screen API | LOW | LOW | P3 |
| App Actions/Assistant voice | LOW | HIGH | P3 (defer indefinitely) |
| Any anti-feature (Play Integrity, in-app review, AAB, billing, etc.) | NONE for this project | N/A | Not applicable — omit from roadmap entirely |

**Priority key:**
- P1: Must have — app is not a usable background music player without it (maps to PRD Fase 6 verification criteria)
- P2: Should have, add when convenient within Fase 5/6
- P3: Nice to have, explicitly deferred past this milestone

## Competitor Feature Analysis

| Platform Capability | Spotify (official app) | Generic streaming-only apps (e.g. internet radio clients) | Our Approach |
|---------|--------------|--------------|-------------|
| Foreground service + MediaSession + MediaStyle notification | Full implementation, long-standing | Full implementation — this is the universal baseline for *any* Android streaming audio app, store-published or not | Same baseline, scoped to personal use (P1 above) |
| Offline download/cache | Core differentiator for Spotify (premium feature) | Usually absent (streaming-only by nature, same as this project) | Explicitly excluded by project constraint; confirmed above that this doesn't block any table-stakes platform feature |
| Android Auto | Fully supported, Play-listed | Mixed — many smaller streaming-only apps skip it | Deferred (Differentiator, not built) |
| Home-screen widget | Supported | Mixed | Deferred (Differentiator, not built) |

## Sources

- [Background playback with a MediaSessionService — developer.android.com](https://developer.android.com/media/media3/session/background-playback) — HIGH confidence, official Media3 guide; confirms foreground service type, manifest declaration, and `FOREGROUND_SERVICE_MEDIA_PLAYBACK` permission requirement for API 34+
- [MediaSessionService reference — developer.android.com](https://developer.android.com/reference/androidx/media3/session/MediaSessionService) — HIGH confidence, official reference
- [AudioFocusRequest reference — developer.android.com](https://developer.android.com/reference/android/media/AudioFocusRequest) — HIGH confidence, official reference; confirms system-handled ducking since API 26 and speech-content-type behavior
- [MediaStyleNotificationHelper.MediaStyle reference — developer.android.com](https://developer.android.com/reference/androidx/media3/session/MediaStyleNotificationHelper.MediaStyle) — HIGH confidence, official reference
- [Build media apps for cars — developer.android.com](https://developer.android.com/training/cars/media) — HIGH confidence for the technical contract (MediaBrowserServiceCompat, content tree); MEDIUM for the claim that Play design-review gating only applies to Play-listed apps (inferred, not explicitly contradicted in the retrieved excerpt)
- [Android 16 behavior changes — developer.android.com](https://developer.android.com/about/versions/16/behavior-changes-16) — HIGH confidence; confirms edge-to-edge enforcement started at API 35 (opt-out removed at API 36) and predictive back defaults to enabled at API 36
- [Doze and App Standby — developer.android.com](https://developer.android.com/training/monitoring-device-state/doze-standby) — MEDIUM confidence; official doc confirms `isIgnoringBatteryOptimizations()`/exemption intents exist, but retrieved excerpt didn't fully resolve the foreground-service-during-Doze network question — treat the "foreground service is exempt while actively running" claim as MEDIUM confidence pending on-device verification in Fase 6
- `ACTION_AUDIO_BECOMING_NOISY` handling pattern — LOW-MEDIUM confidence, corroborated by an open-source MPD Android client implementation and a Xamarin API doc rather than a directly-retrieved official Android guide page (`developer.android.com/guide/topics/media-apps/volume-and-earphones` was referenced by the MPD source but not independently fetched here) — verify the official page directly during Fase 6 implementation
- `android-activity`/winit/cargo-apk2 packaging research — MEDIUM confidence, docs.rs crate pages for `android-activity`, `cargo-apk2`; confirms winit 0.30 pairs with `android-activity` 0.6 and that NativeActivity avoids a Java/Kotlin build step while GameActivity requires Gradle — relevant context for why any JNI-dependent feature above (MediaSession, foreground service) forces at least a minimal Gradle/Kotlin module regardless of which packaging tool is chosen in Phase 1
- Training-data baseline (MEDIUM confidence, standard documented Android behavior, not independently re-verified via search in this pass): single-Activity NativeActivity apps generally own their own in-app back-stack via egui rather than the system `FragmentManager` back stack, which is why predictive back's main practical benefit here is limited to the exit-to-launcher animation

---
*Feature research for: Android platform integration (background playback, media controls) for spotifast-android*
*Researched: 2026-10-14*

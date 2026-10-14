# Pitfalls Research

**Domain:** Porting a Rust + egui (eframe/glow/winit-fork) desktop app with librespot + cpal audio to Android
**Researched:** 2026-10-14
**Confidence:** MEDIUM (mix of verified GitHub issues/docs and WebSearch-corroborated community reports; cpal/AAudio specifics and librespot-oauth-on-Android are LOW confidence — flagged inline)

## Critical Pitfalls

### Pitfall 1: GL surface/context is destroyed on every background/rotate, and naive eframe setups crash or render black on resume

**What goes wrong:**
On Android, `android-activity` (the glue crate winit's Android backend depends on) sends `Resumed` only after a new `SurfaceView`/native window exists, and sends `Suspended` *before* that surface is destroyed. Any EGL/GL surface, and anything that assumes "window exists for the lifetime of the app" (as desktop eframe does), is invalid the instant `Suspended` fires — this happens on every screen-off, backgrounding, split-screen resize, and rotation, not just app kill. egui itself hit this: an eframe regression (emilk/egui#3674) made Android apps panic with `no entry found for key` (missing ROOT viewport) or render a black screen on the hide→resume cycle, because viewport/window state wasn't being torn down and rebuilt correctly around `Suspended`/`Resumed`. It was fixed by PR #3847 ("Fix Android crash on resume") in egui, with a known follow-up issue (#3861), implying the fix area is still fragile.

**Why it happens:**
Desktop GL/glow code (and the `crmne/egui`+`crmne/winit` forks pinned in this project) was written assuming a persistent window/surface. Android's activity lifecycle revokes the native window on every pause, and the app must drop the GL context/surface on `Suspended` and fully recreate it (shaders may survive, but framebuffers, swapchain-equivalent, and sometimes the GL context itself do not) on the next `Resumed`. Any state that doesn't flow through this teardown/rebuild (texture caches, viewport maps, font atlases uploaded to GL) silently goes stale or panics on first access after resume.

**How to avoid:**
- Pin `eframe`/`egui` and the `crmne` forks to commits *at or after* the #3847 fix, and specifically test the hide→resume cycle before relying on any other Android work (this should be close to the very first thing verified in Phase 1, before building out UI).
- Never cache raw GL object handles (textures, VAOs) across a `Suspended` boundary; let egui/glow own re-upload, and audit any `fastframe-*` code that touches GL directly (icons/theme crates) for the same assumption.
- Treat rotation and multi-window resize as "just another Resumed/Suspended pair," not a special case — Android does not guarantee the same surface size/format after resume.
- Because the audio engine (Phase 5) must survive this cycle completely untouched, verify via logs that the Suspended/Resumed GL teardown never touches `src/backend.rs`/`src/player.rs` runtime — if GL code and audio code share any `Mutex`/channel that blocks, a stalled resume can stall audio too.

**Warning signs:**
- Black screen after turning the screen off and back on, or after switching apps.
- Panics referencing viewport IDs, `ROOT`, or `.unwrap()` on window/surface lookups in egui/eframe's Android glue.
- App works in the emulator (which is sometimes lenient about surface destruction timing) but breaks on a real device.

**Phase to address:**
Phase 1 (minimal build) must prove a resume cycle works before anything else is layered on; Phase 6 must re-verify it combined with the foreground service and screen-off playback, since that's the real-world path (AND-09).

---

### Pitfall 2: Audio keeps playing correctly through Suspended/Resumed in testing, then silently stops in real Doze because "foreground service" alone isn't a Doze exemption

**What goes wrong:**
Teams commonly assume `startForeground()` with a notification is sufficient to survive Doze/App Standby indefinitely. In practice, multiple independent reports (forum posts, a Titanium SDK bug) describe audio/background work being throttled or killed roughly 5+ minutes in, especially on OEM-customized Android (Samsung, Xiaomi, etc. — see dontkillmyapp.com) where aggressive battery managers kill processes regardless of the official foreground-service contract. Separately, Android 14 (API 34) *requires* declaring an explicit foreground service type; starting a service for media playback without declaring `android:foregroundServiceType="mediaPlayback"` and holding the `FOREGROUND_SERVICE_MEDIA_PLAYBACK` manifest permission throws `MissingForegroundServiceTypeException` at `startForeground()` time — an immediate hard crash, not a slow throttle. This device's SDK is android-34, so this applies directly.

**Why it happens:**
Doze/App Standby operate independently of the foreground-service API contract on many OEM skins; Google's own guidance (dontkillmyapp-style exemptions) is a baseline, not a guarantee. Developers test on stock/Pixel-like emulators where Doze behaves per-spec, then ship to real devices with vendor battery managers that don't honor it the same way. Separately, the API-34 foreground service type requirement is a compile-time-invisible, runtime-only failure — `cargo check`/`cargo build` won't catch a missing manifest attribute or permission.

**How to avoid:**
- Declare `<service android:foregroundServiceType="mediaPlayback">` plus both `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_MEDIA_PLAYBACK` permissions in the manifest from the first Phase 6 commit, not as an afterthought.
- Build the foreground service around `MediaSessionCompat`/`MediaSession` + `MediaStyle` notification so the OS classifies the app correctly as "media app," which earns better treatment from stock Doze (separate from OEM killers, which this cannot fully control).
- Do not rely on `IGNORE_BATTERY_OPTIMIZATIONS` as the primary defense — treat it as a secondary nudge, and test actual 10+ minute screen-off playback on a real device (not just emulator), as called for in the project's own Phase 6 verification.
- Avoid acquiring a raw `PARTIAL_WAKE_LOCK` unless proven necessary; prefer letting AAudio's own playback stream keep the audio HAL alive and rely on the foreground service for process-level protection — wake locks are a common source of battery complaints and Play-policy flags (not a store-distribution concern here, but still a correctness/battery signal worth avoiding without cause).
- Document real-device-only caveats in Phase 7 stabilization: OEM-specific battery whitelisting may be unavoidable for some vendors and is out of this project's control.

**Warning signs:**
- Playback stops silently after a fixed ~5 minute window with the screen off, no crash in logcat.
- `MissingForegroundServiceTypeException` crash immediately on `startForeground()` on an API 34 device/emulator, even though it worked fine on an older API level emulator.
- Works on emulator, fails identically every time on a specific physical device brand.

**Phase to address:**
Phase 6 (background/media controls) primarily; Phase 5 should at minimum land basic `cfg(target_os = "android")` scaffolding so the audio thread itself never depends on activity lifecycle state.

---

### Pitfall 3: cpal has no first-class Android/AAudio backend — this is a packaging decision, not a tuning problem

**What goes wrong:**
Unlike desktop platforms (ALSA/CoreAudio/WASAPI), cpal does not ship a built-in, enabled-by-default AAudio or Oboe host for Android in the way the project's PRD implicitly hopes (R3 frames this as "confirm support," but the real open question is narrower: whether `cpal` 0.18 compiled for `aarch64-linux-android` produces a working `Host`/`Device` at all, and if so through which native API). Projects that do get native audio working on Android from Rust (e.g., the `wz-phone` codebase found during this research) route Android specifically through Google's Oboe C++ library via a custom `build.rs`/FFI bridge, explicitly bypassing cpal on that target and keeping cpal only for desktop hosts. Teams that assume "cpal just works everywhere cross-compiles" discover the gap only when `cpal::default_host()` returns no devices, or the crate fails to compile at all for the Android target because its lower-level platform dependencies (JNI bindings, NDK audio headers) aren't wired up for that target without an explicit feature/cfg path.

**Why it happens:**
cpal's host abstraction historically targeted desktop OS audio APIs; Android support (when present) is version- and feature-flag-dependent and easy to assume rather than verify. This is compounded by `fastframe-audio` being a wrapper around cpal 0.18 — any gap in cpal's Android support becomes a gap in `fastframe-audio`, and since this is an internal `fastframe-*` crate (R2), it's exactly the kind of external dependency the PRD says must not be vendored/copied into the repo, only tracked as "a dependency to fix upstream or work around."

**How to avoid:**
- Before writing any playback UI work, do a Phase 1/5 spike: compile `fastframe-audio`/cpal 0.18 alone for `aarch64-linux-android` and attempt to enumerate output devices and play a test tone on-device. Treat failure to compile, or an empty device list, as a hard R3 blocker to resolve before continuing Phase 5.
- If cpal's Android backend is missing or broken in 0.18, the realistic options are: (a) patch/upgrade cpal via a pinned fork the same way `[patch.crates-io]` already pins other deps (consistent with R9's existing pattern), or (b) write a minimal Oboe/AAudio-via-JNI sink specific to `src/sink.rs` for Android only, behind `cfg(target_os = "android")`, keeping the desktop `fastframe-audio` path untouched. Decide this explicitly rather than discovering it mid-Phase-5.
- Do not assume emulator audio output validates real-device AAudio behavior — emulator audio paths are notoriously permissive/different from real AAudio buffering; validate on a physical device per the PRD's own Phase 5 verification step.

**Warning signs:**
- `cpal::default_host().devices()` returns empty on Android even though the emulator has an audio output configured in AVD settings.
- Linker errors referencing missing Android audio/JNI symbols when cross-compiling `fastframe-audio` for the first time.
- Playback "works" in the emulator but underruns/crackles or fails to initialize at all on a real device — a classic sign of relying on emulator audio leniency.

**Phase to address:**
Phase 1 should include an audio-compile spike (even before the full UI build) specifically because this blocks or reshapes Phase 5 significantly; Phase 5 is where it must be fully resolved and verified on a real device per AND-06.

---

### Pitfall 4: `RECORD_AUDIO`-style runtime permission assumptions, and sample-rate/format mismatches that only manifest as crackling, not errors

**What goes wrong (LOW confidence, flag for validation):**
Two related but distinct cpal/AAudio issues recur across native-audio-on-Android projects:
1. Developers sometimes gate audio *output* behind a runtime permission prompt by habit (copy-pasting audio *input* boilerplate); playback-only apps do not need `RECORD_AUDIO`, but if cpal/fastframe-audio's host initialization path unconditionally probes input devices (common in cross-platform audio libs that enumerate both directions), it can silently fail or hang waiting on a permission that was never granted because the UI never asked for it.
2. AAudio is picky about sample rate / format negotiation: requesting a stream in a format/rate the hardware doesn't natively support causes AAudio to either resample (adding latency and occasionally audible artifacts) or, in stricter "exclusive mode" stream requests, fail to open the stream at all. Low-level AOSP/WebRTC audio code deliberately treats under-buffering as a `PAUSING` state rather than a reported error (to avoid false underrun reports while a stream is intentionally winding down for pause) — which means a symptom like "playback cuts out briefly on every pause/resume" can look like a librespot/network issue when it's actually AAudio buffer-state handling.

**Why it happens:**
cpal's cross-platform `Device`/`Stream` API doesn't surface AAudio-specific concepts (performance mode, sharing mode, exclusive vs shared streams) in an obvious way, so apps get AAudio's default (safe but higher-latency "shared" mode) without realizing a lower-latency path exists or that format mismatches are happening silently.

**How to avoid:**
- Confirm the app only requests `RECORD_AUDIO` if/when it's actually needed (it almost certainly is not needed for playback-only — verify fastframe-audio doesn't request it as a side effect of enumerating inputs).
- Query the device's native sample rate (`AudioManager.getProperty(PROPERTY_OUTPUT_SAMPLE_RATE)` equivalent, or let AAudio auto-negotiate) rather than hardcoding 44100 Hz; mismatches are the most common source of "sounds slightly off" or extra latency bug reports in Android audio apps.
- When tuning buffer size for low-latency playback (desirable for seek/pause responsiveness), start conservative (let AAudio pick the default buffer) and only shrink it once correctness is proven — this avoids chasing underrun crackle bugs during early Phase 5 work.
- Log actual negotiated sample rate/format on stream open during Phase 5 development builds, so a mismatch is visible in logcat rather than only audible.

**Warning signs:**
- Audio permission dialog appears on an app that should never need microphone access.
- Slight pitch/speed distortion or persistent low-level crackle that doesn't correlate with network/buffering issues from librespot.
- Brief audio glitch specifically on every pause→resume transition (vs. mid-playback), suggesting AAudio pause-state handling rather than a librespot/network stall.

**Phase to address:**
Phase 5 (audio/playback) — include a manual listening-test checklist item specifically for pause/resume and seek, not just "does audio play."

---

### Pitfall 5: Packager choice (R1) is a moving target — cargo-apk's "deprecated" docs.rs notice is stale; xbuild (its suggested replacement) is explicitly unmaintained

**What goes wrong:**
docs.rs for `cargo-apk` 0.10.0 displays a note that it is "deprecated in favour of xbuild." Teams that take this at face value switch to xbuild and lose time, because as of this research the `rust-mobile/xbuild` GitHub repository's own description reads **"Cross compile rust to any platform (unmaintained)"** — the opposite of a safe migration target. Meanwhile `rust-mobile/cargo-apk` itself shows ongoing signs of life (21 open issues, 20 open PRs, active CI) with no archive banner and no in-repo deprecation notice, contradicting its own docs.rs blurb. This is exactly the kind of stale-docs trap the project's own research discipline warns about (negative/deprecation claims need verification against the actual repo, not just a cached docs.rs annotation).

**Why it happens:**
docs.rs caches crate-level README/doc-comment content at publish time; a deprecation note written once doesn't get un-published even if the ecosystem's situation reverses (xbuild losing its maintainer after being positioned as cargo-apk's successor). Nobody re-checks a "deprecated in favor of X" claim once X turns out to have stalled.

**How to avoid:**
- Treat R1's packager decision (Fase 1) as requiring a fresh repo-status check at decision time, not trust in any single doc page: check `rust-mobile/cargo-apk`, `rust-mobile/xbuild`, and `bbqsrc/cargo-ndk` commit/issue activity directly on GitHub before committing to one.
- Given current evidence, `cargo-apk` (still active, purpose-built for "APK from native Rust crate, minimal setup," directly matches this project's single-crate-with-GL-window shape) or `cargo-ndk` (actively tagged with a stated MSRV and changelog, but only builds `.so`/`jniLibs` — needs a minimal hand-written Gradle project to actually assemble an APK, sign it, and declare the manifest attributes Pitfall 2 requires) are the safer starting points over xbuild, which is self-labeled unmaintained and carries 54 open issues / 28 open PRs with unknown resolution status.
- Whichever is chosen, verify it independently supports: the specific `android-activity` base class (`android-native-activity` vs `android-game-activity`) that the pinned `crmne/winit` fork targets, declaring the custom foreground-service manifest entries from Pitfall 2, and multi-ABI output (`arm64-v8a` at minimum, `x86_64` for the emulator per the project's installed targets).
- Document the chosen packager's exact version/commit in `.planning/` (the project already does this for toolchain versions) so later phases don't silently drift to an incompatible version.

**Warning signs:**
- Packager produces an APK that installs but immediately crashes with a `ClassNotFoundException` for the activity class (mismatched `android-activity` base class vs. manifest).
- Gradle/packager step silently drops an ABI (app installs on emulator x86_64 but not on the arm64 test phone, or vice versa).
- Build instructions in Phase 1 docs reference a tool version that no longer matches what `check-android-env.sh` detects.

**Phase to address:**
Phase 1 (build Android mínimo) — this is the first real decision point and should be re-verified against live repo status, not assumed from this research alone (mark LOW-to-MEDIUM confidence and re-check at execution time, since repo maintenance status can change quickly).

---

### Pitfall 6: `[patch.crates-io]` git-pinned forks (egui, winit, librespot) can silently diverge in cross-compilation behavior from what's tested on desktop

**What goes wrong:**
The project pins `crmne/egui`, `crmne/winit`, and `crmne/librespot` by commit via `[patch.crates-io]` (R9). These forks were presumably developed/tested primarily against desktop targets (Linux/macOS/Windows). Cross-compiling a patched dependency to a wholly new target triplet (`aarch64-linux-android`) can expose code paths the fork's maintainer never exercised: `cfg(target_os = "android")` branches that don't exist yet, build scripts that assume a desktop linker/toolchain, or feature flags (`x11`, `wayland`) that are unconditionally enabled upstream and don't make sense on Android but weren't gated out. Any fix needed on the Android side has to go upstream into the pinned fork commit (or a new commit must be pinned) — the project's own constraint ("manter esses commits, não trocar de fonte," AND no new dependencies without justification) means there's no quick local patch available without either (a) advancing the pin to a newer upstream commit that happens to fix it, or (b) maintaining a project-local divergent fork, which contradicts the "don't vendor" spirit found elsewhere in the PRD.

**Why it happens:**
Git-patched dependencies bypass crates.io's version/feature negotiation safety net; a workspace with `[patch.crates-io]` entries pointing at forks effectively freezes the dependency graph to whatever that fork commit's `Cargo.toml` declares, including its own transitive `[patch]`/feature defaults. When that commit predates Android being a consideration for the fork author, cross-compilation is untested territory, and `cargo check --target aarch64-linux-android` is often the *first* time anyone compiles that exact commit for that target.

**How to avoid:**
- Before relying on `cargo check --target aarch64-linux-android` output, check whether the pinned `crmne/egui`/`crmne/winit` commits are *downstream of* (i.e., include) the `#3847` Android-resume fix identified in Pitfall 1 — if the fork was branched before that fix landed upstream in `emilk/egui`, the pin needs to be advanced (and the new commit re-pinned per R9's process) before Phase 1 can be considered done, not after.
- Audit each patched crate's `Cargo.toml` for target-specific feature defaults (`default = ["x11", "wayland"]`-style) that may need `default-features = false` + an explicit Android feature list in *this* project's `Cargo.toml`, since the patch mechanism doesn't let this project edit the fork's own defaults.
- When a cross-compilation failure traces into a patched fork's code (not this project's own `src/`), resist the urge to "quickly fix it locally and move on" — record it as a decision in `.planning/` (new pinned commit vs. temporary cfg-gated workaround in this project's own code) so R9's constraint is honored deliberately, not accidentally violated.
- Treat `librespot-oauth` specifically with suspicion: its documented flow spawns a local HTTP server to catch the OAuth redirect (see Pitfall 7) and was almost certainly designed/tested for desktop loopback use, not a mobile system-browser-to-app handoff — verify early whether the pinned `crmne/librespot` fork has already adapted this for mobile, or whether this is new work the fork doesn't yet support.

**Warning signs:**
- `cargo check --target aarch64-linux-android` fails with an error whose file path is inside `~/.cargo/git/checkouts/...` (a patched dependency) rather than this project's own `src/`.
- A desktop-only Cargo feature (`x11`, `wayland`, `clipboard`) from a patched fork pulls in a transitive crate that itself fails to cross-compile to Android (e.g., an X11 FFI binding).
- Behavior differs between `cargo check` (host) passing and `cargo build --target aarch64-linux-android` failing deep in a patched dependency's own build.rs.

**Phase to address:**
Phase 0/1 — part of the "environment verified" and "build Android mínimo" exit criteria should explicitly include confirming the patched-fork commits are Android-aware, not just that `cargo check --target aarch64-linux-android` happens to succeed today (success today doesn't rule out the Pitfall 1 resume-crash class of bug being present in an un-advanced fork commit).

---

### Pitfall 7: librespot's OAuth flow assumes a loopback HTTP server reachable from "a browser," which needs explicit validation on-device, not assumed to "just work because it's the same device"

**What goes wrong (LOW confidence — flag for on-device validation in Phase 4):**
librespot's `librespot-oauth` crate completes auth by spawning a local HTTP server and expecting the browser to redirect back to it (`http://127.0.0.1:PORT/...`), matching the `redirect_uri` registered with the Spotify client ID exactly. This pattern works naturally on desktop (same OS process space, loopback always reachable, port can be anything since it's all local). On Android, the system browser (Chrome Custom Tabs or similar, launched via `opener.rs`-equivalent) and the app are different processes but on the same device, so loopback *should* still resolve — but Spotify's own current redirect-URI policy explicitly disallows `localhost` (must be an explicit IPv4/IPv6 literal) and Google has been retiring loopback OAuth flows for native mobile apps industry-wide in favor of custom-scheme or verified-App-Link redirects, due to interception risk. Separately, Android's background/battery restrictions (Pitfall 2's family of issues) can affect whether a bound local server stays reachable while the app is backgrounded during the browser hand-off, especially if the app process gets suspended between "opened the browser" and "browser redirects back."

**Why it happens:**
librespot's OAuth implementation was built primarily for desktop/CLI use cases (go-librespot, librespot daemon); nobody has validated it against Android's split-process browser-to-app handoff model, and the exact `redirect_uri` registered for this project's Spotify client ID was chosen without Android in mind.

**How to avoid:**
- Before Phase 4 implementation work, confirm what `redirect_uri` is currently registered with the Spotify client ID this project uses, and whether it's a loopback literal (works only if reachable during the handoff) or something else.
- Test the full flow early and manually: launch system browser from the Android app, complete Spotify login, and confirm the redirect successfully reaches the app's locally bound server — on a real device, not just emulator (emulator loopback networking can behave more permissively than real-device Chrome Custom Tabs sandboxing).
- If the loopback approach proves unreliable on Android (a real possibility given Google's broader move away from it for native apps), the fallback is a custom URI scheme intent-filter (`spotifast://callback`) that a thin Android glue activity catches and hands back into the Rust/JNI layer — this is a standard mobile OAuth pattern but is new code this project doesn't have yet, and would need its own redirect_uri registered with Spotify.
- Read `docs/_reference/how-it-connects.md` (per the project's own mandatory-reading rule) before touching any of this, since it likely documents the current desktop auth flow this needs to adapt from.

**Warning signs:**
- Browser opens and login succeeds, but the app never detects completion (hangs on a spinner) — classic symptom of the redirect never reaching the locally bound server.
- Works when app is in foreground during the whole browser hand-off, fails if the user switches away from the browser back to the app manually instead of the browser auto-returning.
- Spotify API returns `INVALID_CLIENT: Insecure redirect URI` — indicates the registered `redirect_uri` doesn't match Spotify's current (post-2025 policy change) requirements.

**Phase to address:**
Phase 4 (login e credenciais) — this should be one of the first things spiked in that phase, since it may require registering a new redirect URI or writing new Android-glue code, both of which have lead time.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|-----------------|-----------------|
| Testing GL resume/lifecycle only on emulator | Faster iteration, no device needed | Emulator is more lenient about surface destruction timing than real devices; Pitfall 1-class bugs hide until real-device testing | Only for the very first "does it launch" smoke test in Phase 1; never as the final signal before calling a phase done |
| Acquiring a raw partial wake lock "just to be safe" for audio | Audio definitely doesn't stop | Battery drain, masks real Doze/foreground-service misconfiguration (Pitfall 2), harder to debug later | Never as a first resort — only as a diagnostic (temporarily) to isolate whether a stoppage is Doze-related |
| Hardcoding a 44100 Hz output format in the Android sink | Simpler code, matches librespot's typical stream rate | AAudio resamples silently, adding latency/artifacts on devices whose native rate differs (commonly 48000 Hz) | Acceptable as an interim Phase 5 milestone, must be replaced with native-rate query before Phase 7 stabilization |
| Advancing a pinned fork commit without re-reading its diff against the old pin | Saves review time | Could silently pull in unrelated desktop-breaking changes, violating the "don't break desktop" constraint (AND-02) | Never — always diff-review before re-pinning per R9 |
| Leaving `mdns-sd`/`zeroconf.rs` (R6) compiled in but non-functional on Android rather than `cfg`-gating it out | Less code to touch now | Multicast-lock permission errors or silent no-op Spotify Connect discovery confuse later debugging | Acceptable only if explicitly logged/disabled behind a flag, not silently broken |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|-------------------|
| Android foreground service (media) | Declaring `FOREGROUND_SERVICE` permission but omitting the API-34-required `FOREGROUND_SERVICE_MEDIA_PLAYBACK` permission + `foregroundServiceType="mediaPlayback"` | Declare both from the first Phase 6 commit; this is a manifest-only, compile-invisible requirement |
| Spotify OAuth redirect | Reusing the desktop `redirect_uri`/loopback flow unchanged on Android | Verify redirect reachability through the real system-browser-to-app handoff on-device before building UI around it (Pitfall 7) |
| mDNS/Spotify Connect discovery (`mdns-sd`, `zeroconf.rs`) | Assuming multicast "just works" like on desktop Linux | Acquire `WifiManager.MulticastLock` (R6) and declare `CHANGE_WIFI_MULTICAST_STATE`, or explicitly disable discovery on Android if not essential to AND-06's scope |
| JNI calls from the audio thread (e.g., for AAudio/Keystore/MediaSession callbacks) | Attaching to the JVM once and never detaching, or attaching repeatedly without matching detach, from a thread cpal/Oboe spawns that Rust doesn't control the lifecycle of | Wrap attach/detach in a scope guard tied to the actual native thread lifetime; name the thread when attaching (some ART versions warn on unnamed native threads) |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|-----------------|
| LTO + full desktop dependency graph compiled for NDK targets (R8) | `cargo build --target aarch64-linux-android` takes many minutes per iteration | Use a fast dev profile (`lto = false`, `opt-level = 1`, `codegen-units` high) for Android dev builds; keep release-profile LTO only for a final stabilization build | Becomes painful starting Phase 1 once the full app (not a hello-world) is compiled for Android; gets worse every phase that adds code |
| Shared default buffer size on AAudio | Playback "works" but has 200ms+ perceptible lag on seek/pause/resume | Query/negotiate buffer size deliberately once correctness is proven (Pitfall 4); don't chase this prematurely | Noticeable once real users (or the developer) do rapid seek/pause testing in Phase 5-6 |
| Rebuilding GL textures/font atlas on every resume without caching source data | Visible flash/delay every time the screen turns back on | Keep font/texture *source* data (not GL handles) resident in Rust memory so re-upload after Suspended is fast, not a full re-decode | Noticeable any time the user locks/unlocks frequently, i.e., constantly in real usage |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Falling back to on-disk credential storage if Android Keystore (R4) integration is incomplete, "just for now" | Credentials in plain/JSON storage on-device, contradicts the project's own `AGENTS.md` and PRD constraint | Treat R4 (Keystore via JNI) as a hard blocker for AND-05; do not merge a fallback path that writes credentials outside Keystore, even temporarily, per the project's own no-plain-JSON-credentials rule |
| Using a custom URI scheme for OAuth redirect without validating the incoming intent | Another installed app could register the same scheme and intercept the auth code (well-documented Android deep-link risk) | If Pitfall 7 forces a custom-scheme fallback, validate the intent's calling package where possible and treat the receiving activity as untrusted input, not just "my own app talking to itself" |
| Logging librespot/OAuth debug output on Android (easier to leave verbose logcat on during development) | Tokens/credentials leak into logcat, which is more broadly accessible on a dev device (ADB, bug report tools) than a desktop log file | Audit log statements added during Phase 4/6 debugging for credential leakage before Phase 7; logcat is a more exposed surface than desktop stdout |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-------------------|
| Treating rotation/backgrounding as rare edge cases to "handle later" | App appears broken/crashy within the first few seconds of real use (screen auto-locks constantly) | Treat Pitfall 1's resume cycle as a Phase 1 blocking requirement, not a Phase 6 polish item |
| No visual/audio feedback while OAuth browser hand-off is in progress | User unsure if login is stuck or working, especially if Pitfall 7's loopback timing is flaky | Show explicit "waiting for browser" state in Phase 4 UI, with a manual-retry/fallback path |
| Ignoring audio focus (another app/call interrupting playback) until Phase 6 | Music keeps blaring over a phone call or another app's audio during earlier phase testing, giving false confidence that playback "just works" | AND-09 already lists audio focus — verify it specifically during Phase 5 manual testing, not deferred entirely to Phase 6 |

## "Looks Done But Isn't" Checklist

- [ ] **APK builds and installs:** Often missing a correct `foregroundServiceType`/permission pair for API 34 — verify by actually calling `startForeground()` on a real/emulated API 34 device, not just checking it compiles.
- [ ] **Playback works in testing session:** Often only verified with the screen on and app foregrounded — verify specifically through a screen-off 10+ minute session (per AND-07/the PRD's own Phase 6 check) and after a real Doze-idle window, not just immediately after locking.
- [ ] **Login works:** Often only tested once, right after implementation, with the browser and app both warm — verify by force-closing the browser mid-flow, and by re-opening the app after a device reboot to confirm Keystore-backed persistence (AND-05's "fechar o app, reabrir e continuar logado").
- [ ] **Resume-from-background renders correctly:** Often only tested with a quick tap away/back — verify after a genuine multi-minute background period (OS may have done more aggressive resource reclamation) and after an actual rotation, not just a resize in the emulator's rotate button.
- [ ] **Desktop build "still passes":** Often verified with `cargo check` only — per the project's own constraint, confirm `cargo test`/existing test suite still passes on desktop too, since `cfg(target_os = "android")` gating mistakes can silently alter desktop behavior without a check-level error.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|----------------|-----------------|
| Pitfall 1 (GL resume crash) | LOW if caught in Phase 1 | Advance pinned egui/winit fork commits past the upstream fix, or cherry-pick the fix into the fork's pin; re-verify resume cycle |
| Pitfall 3 (cpal has no working Android backend) | HIGH if discovered late in Phase 5 | Fall back to a `cfg(target_os = "android")`-gated minimal Oboe/AAudio JNI sink in `src/sink.rs`, isolated from the desktop cpal path; budget real time for this, it's effectively new platform code |
| Pitfall 5 (wrong packager chosen) | MEDIUM | Packager choice is largely isolated to build tooling/scripts, not application code; switching mid-project costs CI/doc rework but not a rewrite, provided Gradle/manifest knowledge gained is reusable |
| Pitfall 7 (OAuth loopback doesn't work on Android) | MEDIUM-HIGH | Requires registering a new redirect URI with Spotify and adding a thin Android intent-filter glue activity; plan for this as a distinct Phase 4 sub-task rather than discovering it blocks AND-05 entirely |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|-------------------|---------------|
| 1. GL surface/context lost on Suspended/Resumed | Phase 1 (minimal build), re-verified Phase 6 | Lock/unlock and rotate the device repeatedly after the minimal "hello egui" build renders; no black screen, no panic in logcat |
| 2. Foreground service + Doze killing audio | Phase 6 | 10+ minute screen-off playback on a real API-34 device; confirm `foregroundServiceType="mediaPlayback"` declared and no `MissingForegroundServiceTypeException` |
| 3. cpal/AAudio Android backend gap | Phase 1 spike, resolved Phase 5 | `fastframe-audio`/cpal compiles for `aarch64-linux-android` and `cpal::default_host().devices()` returns a real device before any playback UI work begins |
| 4. Sample rate/permission mismatches | Phase 5 | Manual listening test for crackle/pitch issues on pause/resume/seek; confirm no unexpected `RECORD_AUDIO` prompt |
| 5. Packager choice (cargo-apk vs xbuild vs cargo-ndk) | Phase 1 | Re-check live maintenance status of all three on GitHub at decision time, not from this document alone; document chosen tool + version in `.planning/` |
| 6. Patched-fork cross-compilation divergence | Phase 0/1 | Confirm pinned egui/winit/librespot fork commits are downstream of known Android fixes (e.g., egui #3847) before declaring Phase 1 done |
| 7. librespot OAuth loopback on Android | Phase 4 | Full manual login flow test on a real device with the browser genuinely backgrounded/foregrounded during redirect, not just emulator |

## Sources

- [emilk/egui#3674 — "eframe's Event::Resumed on Android panics"](https://github.com/emilk/egui/issues/3674) — HIGH confidence (direct GitHub issue, confirmed root cause and fix PR #3847, follow-up #3861)
- Android developer docs — `GLSurfaceView.Renderer` EGL context loss on resume (developer.android.com) — HIGH confidence (official docs)
- Android developer docs — foreground service types required on API 34 (`developer.android.com/about/versions/14/changes/fgs-types-required`, `developer.android.com/guide/components/fg-service-types`) — HIGH confidence (official docs)
- Titanium SDK JIRA bug AC-6117 — media stream stopped by Doze after ~5 minutes, fixed by battery optimization exception — MEDIUM confidence (single bug tracker report, but consistent with multiple community forum reports found separately)
- `dontkillmyapp.com`-style OEM battery-killer reports (community forum threads, AppInventor/Thunkable communities) — LOW-MEDIUM confidence (anecdotal, but consistent pattern across multiple independent threads)
- `wz-phone` project source (git.manko.yoga) — Android audio routed through Oboe C++ bridge, cpal used only on desktop hosts — MEDIUM confidence (one real-world project's concrete implementation choice, not an official cpal statement)
- AOSP/OmniROM gerrit — AAudio `PAUSING` state to avoid false underrun reports — MEDIUM confidence (platform source code behavior)
- WebRTC `aaudio_player.h`/`audio_track_jni.h` — thread attach/detach and buffer-size-on-underrun patterns — MEDIUM confidence (production codebase, not Rust-specific but directly analogous JNI/AAudio patterns)
- `docs.rs/crate/cargo-apk` — deprecation note pointing to xbuild — LOW confidence, directly contradicted by next source
- `github.com/rust-mobile/xbuild` — repository description states "(unmaintained)" — HIGH confidence (direct repo description, overrides the stale docs.rs note)
- `github.com/rust-mobile/cargo-apk` — no archive/deprecation banner, active issues/PRs, signing-profile docs for debug keystore — MEDIUM confidence (repo appears active at time of research, but exact last-commit date unverified)
- `github.com/bbqsrc/cargo-ndk` — active repo signals, `.so`-only scope (no APK packaging), `--link-libcxx-shared` flag, `CARGO_NDK_PLATFORM` for API level — MEDIUM confidence
- Android developer docs — `WifiManager.MulticastLock`, `CHANGE_WIFI_MULTICAST_STATE` permission, API 37+ `ACCESS_LOCAL_NETWORK` — HIGH confidence (official docs)
- `docs.rs/librespot-oauth` — loopback HTTP server / stdin manual-code flow description — MEDIUM confidence (official crate docs, but no explicit mobile guidance, so Android applicability is inferred, not confirmed — LOW confidence specifically for the Android implications)
- Spotify developer docs — redirect URI rules (`localhost` disallowed, must use explicit loopback literal), February 2025 custom-scheme policy note — MEDIUM confidence (official docs + one corroborating community bug report)
- Android developer docs — deep link / custom scheme interception risk (oversecured.com writeup, AppAuth Android patterns) — MEDIUM confidence

---
*Pitfalls research for: Rust + egui + librespot + cpal desktop-to-Android port*
*Researched: 2026-10-14*

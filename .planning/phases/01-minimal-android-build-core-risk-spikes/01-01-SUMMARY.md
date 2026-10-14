---
phase: 01-minimal-android-build-core-risk-spikes
plan: 01
subsystem: infra
tags: [cargo-apk, docker, ci, desktop-gate, egui, glow, android-env]

# Dependency graph
requires: []
provides:
  - "cargo-apk git HEAD installed and live-verified (D-01), SHA recorded"
  - "scripts/check-android-env.sh exits 0 with zero [FAIL]"
  - "D-06 fork-ancestry proof against the correct glow PR (#3867), not the wgpu PR (#3847)"
  - "scripts/desktop-check.sh — CI-equivalent desktop gate (host or Docker), --quick/full modes"
  - "Recorded pre-change desktop baseline (fmt/check/clippy PASS; test 1169 passed/1 failed/3 ignored) for later AND-02 comparisons"
affects: ["01-02", "01-03", "01-04", "every later Phase 1+ plan that needs to prove AND-02"]

# Tech tracking
tech-stack:
  added: ["cargo-apk (rust-mobile/cargo-apk, git HEAD, commit 887423a9150df52f6699332ba39e58ae4c24c877)"]
  patterns:
    - "Desktop CI gate reproduced locally via a disposable Docker image (rust:1.98.0-bookworm) when host lacks pkg-config/ALSA/cmake, auto-detected vs explicit --host/--docker"
    - "Docker test containers need --ulimit nofile raised above the 1024 default — the full spotifast test suite opens enough concurrent sockets/temp files/async runtimes to exhaust it and produce false TooManyOpenFiles failures"

key-files:
  created: ["scripts/desktop-check.sh"]
  modified: []

key-decisions:
  - "Installed cargo-apk from git HEAD (887423a9), not the stale crates.io 0.10.0, per D-01; live-reverified the repo is not archived and was pushed 2026-04-08"
  - "D-06 audit cites PR #3867 (glow_integration.rs fix), not #3847 (wgpu-only) — spotifast's eframe uses default-features=false with glow and no wgpu (Cargo.toml line 35), so #3847 does not apply"
  - "Raised the Docker gate container's nofile ulimit to 65536 after discovering the default 1024 caused 233/242 test failures to be a container artifact, not real regressions — fixed inline (Rule 1) before baselining"
  - "Accepted one baseline test failure (app::tests::mpris_search_links_open_search_on_a_private_bus) as an environment limitation of running as a numeric, passwd-less UID inside the container, not a code defect; later plans should not expect this to disappear from this specific gate without a container passwd-entry fix"

requirements-completed: [AND-00, AND-02]

duration: ~80min
completed: 2026-10-14
---

# Phase 1 Plan 1: Tooling and Desktop Baseline Summary

**cargo-apk (git HEAD) installed and live-verified, AND-00 env check passing, D-06 glow-fork ancestry proven against PR #3867, and a Docker-based desktop-check.sh gate with a recorded pre-change baseline (fmt/check/clippy PASS, test 1169/1170 passing) for all later Phase 1 plans to compare against.**

## Performance

- **Duration:** ~80 min (dominated by two full cold Docker builds of the dependency graph, including libprojectM via CMake)
- **Completed:** 2026-10-14
- **Tasks:** 2
- **Files modified:** 1 (`scripts/desktop-check.sh`, new)

## Accomplishments

- Re-verified D-01 live: `rust-mobile/cargo-apk` is not archived, last pushed 2026-04-08; installed via `cargo install --git ... --locked cargo-apk`, confirmed `cargo apk --help` lists `build`/`run`/`check`/`gdb`, recorded commit `887423a9150df52f6699332ba39e58ae4c24c877`.
- `bash scripts/check-android-env.sh .` exits 0 with zero `[FAIL]` lines (one expected `[WARN]` — no device connected yet, resolved in plan 01-03).
- Proved D-06 against the correct PR: `git merge-base --is-ancestor 200051d5... ba6790fe...` in the pinned `crmne/egui` db exits 0. `200051d5` is "Fix Android crash on resume with Glow backend (#3867)", 2024-01-24. The previously-cited PR #3847 only touches `wgpu_integration.rs`; spotifast's `eframe` dependency is `default-features = false, features = [... "glow" ...]` (Cargo.toml line 35) with no `wgpu`, so #3847 is irrelevant and #3867 is the fix that matters.
- Built `scripts/desktop-check.sh`: runs fmt/check/clippy/test exactly as CI does, auto-detecting host vs. Docker (this host lacks `pkg-config`, ALSA dev headers, and `cmake`, so Docker mode is used), with `--quick` (fmt+check only) and full modes.
- Ran the full baseline twice against the unmodified pre-phase tree (commit `01e3c0c`): the first run surfaced a container-environment bug (see Deviations) which was fixed, then the baseline was re-recorded cleanly.

## Task Commits

Only Task 2 produced a repository change (Task 1 is pure tooling install + verification; its evidence is recorded in this SUMMARY per the plan's own instruction, not a commit):

1. **Task 1: Install cargo-apk, pass env check, run D-06 audit** — no commit (no repo files changed; evidence above and in Deviations/Decisions)
2. **Task 2: Create scripts/desktop-check.sh and record baseline** — `a013c0c` (feat)

**Plan metadata:** pending (this SUMMARY + STATE/ROADMAP update commit)

## Files Created/Modified

- `scripts/desktop-check.sh` - CI-equivalent desktop gate runner (fmt/check/clippy/test), host-or-Docker auto-detect, `--quick`/full modes, tees to `target/desktop-ci/desktop-check-<UTC timestamp>.log`

## Decisions Made

- cargo-apk git HEAD (commit `887423a9150df52f6699332ba39e58ae4c24c877`), not crates.io 0.10.0 — per D-01, live-reverified not archived.
- D-06 cites PR #3867 (glow fix), explicitly correcting earlier CONTEXT.md/PITFALLS.md references to #3847 (wgpu-only, inapplicable since spotifast never enables the `wgpu` eframe feature).
- Docker container's `--ulimit nofile` raised to `65536:65536` — the default 1024 is insufficient for this test suite under parallel execution.
- The one remaining baseline test failure (`mpris_search_links_open_search_on_a_private_bus`) is accepted as a container-environment limitation (numeric UID has no `/etc/passwd` entry, so `dbus-daemon` can't service the private bus) rather than fixed, since fixing it would mean adding NSS/passwd shims to the Docker image — out of scope for a build-tooling plan that changes no Rust source.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Docker gate container's default file-descriptor ulimit caused false test failures**
- **Found during:** Task 2 (first baseline run)
- **Issue:** The first full baseline run reported 242/1170 test failures. Inspecting panic messages showed 233 of them were `Os { code: 24, kind: TooManyOpenFiles, message: "Too many open files" }` — the container's default `ulimit -n` (1024) was exhausted by the test suite's concurrent sockets/temp files/per-test async runtimes, not a real regression in spotifast.
- **Fix:** Added `--ulimit nofile=65536:65536` to the `docker run` invocation in `scripts/desktop-check.sh`.
- **Files modified:** `scripts/desktop-check.sh`
- **Verification:** Re-ran the full baseline; failures dropped from 242 to 1, and the single remaining failure's panic message is unrelated to file descriptors (dbus/UID lookup, see Decisions).
- **Committed in:** `a013c0c` (part of Task 2 commit — the fix was applied before the first commit of this file, so the committed script already has the correct ulimit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Necessary for the baseline to be meaningful — without the ulimit fix, the "baseline" would have falsely shown ~20% of the suite failing for a reason entirely specific to this Docker container, which later plans could not have usefully compared against. No scope creep: the fix is confined to the new gate script, not to spotifast's own code or Cargo.toml.

## Issues Encountered

- First baseline run (before the ulimit fix) took approximately 25 minutes under heavy swap pressure (host has 6GB RAM / 4GB swap, with several unrelated Docker containers already running). The second run was much faster (~2 minutes) because fmt/check/clippy reused fully-cached incremental artifacts in the bind-mounted `target/desktop-ci`, and the ulimit fix only required recompiling `test`-profile build scripts, not the whole dependency tree.
- The host remains unable to run the gate natively: no `pkg-config`, no ALSA dev headers, no `cmake`. This was already known from planning (RESEARCH.md) and is exactly why `scripts/desktop-check.sh` defaults to Docker mode.

## User Setup Required

None - no external service configuration required. (Docker, already available and usable without `sudo` via the `docker` group, is the only infrastructure dependency, and it is installed on this host.)

## Next Phase Readiness

- AND-00 is satisfied: `scripts/check-android-env.sh` exits 0, zero `[FAIL]`.
- The packaging tool for D-01 (cargo-apk, git HEAD) is installed and ready for plan 01-02's first APK build attempt.
- D-06's fork-ancestry proof is complete and correctly scoped to the glow backend spotifast actually uses.
- `scripts/desktop-check.sh` and its recorded baseline (`target/desktop-ci/desktop-check-20261014T143314Z.log`, not committed — gitignored under `target/`) give every later Phase 1+ plan a mechanical way to prove AND-02 ("no NEW failure versus this baseline"). The baseline's one known failure (`app::tests::mpris_search_links_open_search_on_a_private_bus`) should be treated as a pre-existing, environment-specific gate artifact — not a regression to chase if it still fails after a later plan's changes.
- No blockers for plan 01-02 (first Android APK build attempt).

## Known Stubs

None - this plan creates tooling and evidence only; no UI or data-wiring code was touched.

## Threat Flags

None - no new network endpoints, auth paths, file-access patterns, or schema changes were introduced beyond what the plan's own threat model already covers (cargo-apk git install, Docker gate image, fork pins).

---
*Phase: 01-minimal-android-build-core-risk-spikes*
*Completed: 2026-10-14*

## Self-Check: PASSED

- FOUND: `scripts/desktop-check.sh` (executable)
- FOUND: `.planning/phases/01-minimal-android-build-core-risk-spikes/01-01-SUMMARY.md`
- FOUND: `target/desktop-ci/desktop-check-20261014T143314Z.log` (baseline log, gitignored)
- FOUND: commit `a013c0c` in git history
- FOUND: `~/.cargo/bin/cargo-apk` executable
- All claims in this SUMMARY verified against disk and git state.

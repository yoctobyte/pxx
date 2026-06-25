# Next session — Track B (libraries / demos) continuation prompt

Paste into a fresh Track B agent. Snapshot taken 2026-06-25, pinned **stable
v66**. Read `CLAUDE.md` + `docs/dev/parallel-tracks.md` first (track split,
stable-binary boundary). You are **Track B**: own `lib/rtl`, `lib/pcl`,
`examples/**`, `test/lib_*`; never touch `compiler/**`; build with
`$(PXX_STABLE)` (= `stable_linux_amd64/default/pinned`), never rebuild the
compiler.

## Where things stand

- **Green on v66:** `make lib-test` (incl. `mandelbrot` + `raytracer`) and
  `make library-suite`. `make demos` only FAIL = `adventure` (a long platonic
  march — see below), which is expected/tracked, not a regression.
- **Discovery loop is the method:** real apps as probes. Every demo ships a
  deterministic integer CHECKSUM as its oracle (cross-target + future-opt net).
  When platonic code hits a compiler/codegen gap, file a Track A ticket in
  `docs/progress/backlog/` with a *minimal* repro and keep the demo idiomatic —
  do **not** add silent workarounds. (If an idiomatic construct like `const`
  record params doubles as a sidestep, that's fine; note it in the ticket.)
- **This session's demos landed:** `examples/mandelbrot` (Int64 Q4.28
  fixed-point kernel, colour PPM, `--bench`) and `examples/raytracer` (records,
  reflections, colour PPM **and real PNG** via the png/zlib RTL, deterministic
  checksum 297935246). Both wired into `make lib-test`. mandelbrot is kept
  PPM-only on purpose — it's in the Track A float-determinism cross gate and
  pulling png/image/zlib would break its aarch64/arm32 cross-build.

## Bugs filed this session (Track A owns the fixes)

Already FIXED + verified (sis pinned v60–v66): char-literal concat (v60),
const string/literal indexing (v61), textfile ambient in units (v62), plain
by-value record temp (v63), int→float arg conversion (v64), aarch64/arm32 record
temp by-value arg (v65), Single field/element in aggregate (v66).

Still OPEN (filed by us, waiting on Track A — just keep an eye, don't fix):
- `feature-arm32-large-aggregate-result` — arm32 can't return a >4-word record
  (e.g. 24-byte `Vec3`); blocks raytracer on arm32 only (host + aarch64 fine).
- `bug-bare-read-write-in-method-hits-intrinsic` — incl. the `Move` data point
  from adventure (bare intrinsic-named method call binds to the intrinsic).
- Older record/pointer family: `bug-setlength-record-field-via-var-param`,
  `bug-managed-length-via-pointer-deref`, `bug-pointer-deref-not-accepted-as-var-arg`,
  `bug-pchar-to-string-implicit-conv`, `bug-generic-class-methods-in-program`,
  `bug-virtual-keyword-name-result`, `bug-string-const-index-and-typed-init`.

## Cheap cleanup now unblocked (optional, low priority)

v63 + v65 fixed the record-temp bugs the raytracer worked around. The demo still
uses `const` vector params (v63) and a named `TRGBA c` before `ImageSetPixel`
(v65). Both are *idiomatic anyway*, so this is cosmetic — only revert if doing a
pass on the file. Not worth a dedicated session.

## Next Track B work (pick one; discovery-loop priority)

Goal each session: grow `lib-test` green, turn a `make demos` FAIL into OK, file
Track A tickets for blockers. Acceptance for a demo/library = its paired test
compiles + runs correct output against the pinned stable, ideally with a
deterministic checksum oracle.

Candidates, roughly by bug-surface value:
1. **A new compute/visual demo** that stresses an under-probed area — e.g.
   `feature-demo-chess` (already compiles; could grow a perft/checksum oracle —
   great for move-gen + recursion + arrays), `feature-demo-mandelbrot-gui-threaded`
   (threads + GUI), or a small physics/particle sim (more record-by-value, now
   that the record bugs are fixed — good regression pressure).
2. **A self-contained library** with a paired demo oracle:
   `feature-random-library` (PRNG, deterministic), `feature-dns-resolver-library`,
   `feature-copy-intrinsic` (string + dynarray `Copy`).
3. **adventure** (`examples/adventure`) — biggest single platonic target, but a
   long march: F1 (textfile) now cleared by v62; next blocker is the `Move`
   intrinsic-shadow at engine.pas:1038, then F2 (`{$I-}`/`IOResult`), F3 (nested
   proc capture), F5 (`for..in`), etc. See `examples/adventure/EXPECTED-FAILURES.md`.
   Each blocker is a Track A ticket; chip one rung at a time.

Not Track B right now: the **C frontend** (sqlite/lua ladder) — roadmap is in
`docs/developer/plan-c-frontend-test-ladder.md`, but it's Track A / deferred; the
user is staying on the Pascal track.

## Workflow reminders

- `git pull --rebase` at start (`git log --oneline -8` to see what sis pinned);
  small commits; regenerate `docs/progress/BOARD.md` with `tools/progress.sh
  board-md` after any ticket move; push freely when your lane is green.
- Re-test your still-open filed bugs against the current pin — sis fixes fast;
  close (move to `done/`) anything now passing, with a one-line resolution note.
- Verify cross-gate safety before committing anything mandelbrot touches: it's in
  the Track A `test-float-determinism` gate (i386/aarch64/arm32). Other demos are
  host-only (lib-test) and freer.

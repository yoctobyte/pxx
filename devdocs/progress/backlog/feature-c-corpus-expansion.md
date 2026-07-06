# C test-corpus expansion: c-testsuite → zlib → tcc (+ csmith fuzz harness)

- **Type:** feature (C frontend validation) — Track A/C.
- **Status:** backlog — planned 2026-07-06, order agreed with user ("variation is good").
- **Context:** corpus today = lua 5.4 + sqlite 3.46, both green and byte-identical
  to same-version gcc oracles on all targets. Recorded lesson (v185): big feature
  suites hide whole feature classes behind green CRUD — breadth beats depth.

## The plan, ranked by variation-per-effort

### 1. c-testsuite (FIRST — cheapest, broadest)
- https://github.com/c-testsuite/c-testsuite — exactly 220 single-file
  conformance programs (`tests/single-exec/00001.c`..`00220.c`), each isolating
  one C corner (promotion edges, struct passing, bitfields, declarators).
- **No toolchain dependency (verified 2026-07-06 against the repo tree):** the
  suite is pure DATA. Contract: `main` is the entry point, and `NNN.c.expected`
  must match the test's stdout+stderr (220 .c / 220 .expected, 1:1). The
  repo's own runner infra (POSIX sh + Python3 + TAP + TMSU tag queries) is only
  THEIR multi-compiler CI for the daily results page — we bypass it. Their
  per-compiler runners are ~10-line `CC=x` shell wrappers around a generic
  `runners/single-exec/posix` script, paired with a `<name>.skip` file — we can
  mirror that shape (pxx runner + pxx.skip) or write our own loop; either is
  trivial.
- Each test also has `NNN.c.tags` metadata (C-standard level, portability,
  arch assumptions) — ready-made input for the explicit skip-list, no
  guessing why a test is out of scope. No silent skips.
- Graduate later to gcc c-torture `execute/` (~1500 tests) once green.

### 2. zlib (quick win, new workload class)
- Bit-twiddling, huffman tables, CRC loops, unsigned saturation, fn-ptr
  dispatch — different muscle than lua/sqlite. ~25k LOC.
- Oracle: round-trip + `minigzip`/`example.c` output byte-compare vs gcc build.
- Bonus cross-validation: same vectors against our existing PASCAL zlib in
  lib-test — two implementations, one truth.
- Vendor via tools/install_lib_candidates.sh pattern (gitignored, PROVENANCE.md).

### 3. tcc — Tiny C Compiler (the milestone)
- Stresses what nothing else does: setjmp/longjmp error recovery, giant switch
  dispatch, token machinery, its own ELF writer doing raw pointer surgery.
- Ladder: pxx-built tcc runs → compiles hello.c → compiles TCC ITSELF →
  byte-identical to gcc-built-tcc-compiling-tcc. Compiler-compiling-compiler.
- Earned side effect: tcc becomes a SECOND oracle for the whole C corpus
  (triangulate gcc). Multi-session effort.

### 4. csmith differential fuzzing (parallel, ongoing harness)
- Random C generator; run pxx-vs-gcc binaries, diff outputs; creduce minimizes
  hits. Finds miscompiles automatically, forever. One-time harness, then it
  runs overnight. Start once (1) lands.

### 5. Duktape (later, if appetite)
- JS engine, sqlite-style single-file amalgamation, portable C89/99, no
  computed-goto dependency (QuickJS/micropython want computed goto — their
  fallbacks are slow paths). New class: GC + IEEE-754 edge semantics (would
  have caught the v186 float-literal bug from another angle).

## COPY-PASTE KICKOFF PROMPT (fresh session)

You are Track A/C (compiler + C frontend), master. Task: land step 1 of the C
corpus expansion — the c-testsuite conformance battery — per
devdocs/progress/backlog/feature-c-corpus-expansion.md (read it; order and
rationale are settled, do not re-litigate).

1. Vendor https://github.com/c-testsuite/c-testsuite via the
   tools/install_lib_candidates.sh pattern (gitignored like sqlite/lua vendor
   sources, add PROVENANCE.md with commit hash). Tests live in
   tests/single-exec/*.c with expected outputs alongside.
2. Build a runner (script + make target, e.g. `make test-c-conformance`):
   for each test, compile with ./compiler/pascal26 -Ilib/crtl/include
   -Ilib/crtl/src, run, compare exit code/output vs expected (and vs a gcc
   -no-pie build where the suite lacks an expectation). Summary line:
   pass/fail/skip counts.
3. Triage failures: each one is either (a) a cfront/codegen bug — reduce to a
   minimal repro, fix or file a ticket per lane rules (shared internals = Track
   A ticket; you are A/C combined so you may self-resolve), or (b) a legit
   unsupported feature — add to an EXPLICIT skip-list file with one-line reason
   (no silent skips).
4. Gate: runner green (skips documented), make test + self-host byte-identical,
   test-lua-cross 24/24, sqlite suite still byte-identical vs same-version gcc
   oracle (build oracle with extra TU `const char sqlite3_version[]="3.46.0";`
   — see done/bug-c-create-trigger-huge-alloc-oom.md for why).
5. Commit runner + skip-list; wire into make test only if fast enough (<~30s),
   else standalone target documented in BOARD/ticket. Then move this ticket's
   step 1 to done-notes and leave steps 2-5 in backlog.

Steps 2 (zlib) and 3 (tcc) are separate sessions — do not start them unless
step 1 lands early and gates are green.

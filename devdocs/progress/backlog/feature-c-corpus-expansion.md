# C test-corpus expansion: c-testsuite → zlib → tcc (+ csmith fuzz harness)

- **Type:** feature (C frontend validation) — Track A/C.
- **Status:** backlog — planned 2026-07-06, order agreed with user ("variation is good").
- **Step 1 DONE 2026-07-06:** c-testsuite vendored (install_lib_candidates.sh
  c-testsuite), runner `tools/run_c_conformance.sh` + `make test-c-conformance`.
  **Baseline 172/220 pass on pristine master**; all 48 fails are recorded
  ticket-by-ticket in `test/c-conformance/pxx.skip` and filed as 22 backlog
  tickets (bug-c-init-designated-and-nested is the big cluster — 9 tests,
  silent wrong values). NOTE: a prior session drafted 3 inline fixes without
  tickets; per workflow they were REVERTED into tickets (draft approach
  recorded in each): feature-c-crtl-bind-hand-declared-prototypes,
  bug-c-string-literal-binop-decay, bug-c-ptrdiff-of-addr-elem — the last
  because the draft regressed test-core b133. Next inside step 1: burn down
  the skip list ticket by ticket; then step 2 (zlib).
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

### 2. zlib (quick win, new workload class) — STARTED 2026-07-06
See [[feature-c-corpus-zlib]]: vendored (v1.3.1), `test/zlib/runner.c` +
`make test-zlib`, gcc oracle green. Two compiler blockers filed
([[bug-c-typedef-name-as-uninitialized-local]] + a zlib.h `gzgetc` macro parse
bug). libc-gap collector: [[feature-crtl-implement-libc-assumptions]].

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
devdocs/progress/backlog/feature-c-corpus-expansion.md (read it first; order
and rationale are settled with the user, do not re-litigate).

Verified facts (2026-07-06, do NOT re-derive): the suite is pure data — exactly
220 tests `tests/single-exec/00001.c`..`00220.c`, contract = `main` entry +
`NNN.c.expected` matches stdout+stderr, plus `NNN.c.tags` metadata (C-standard
level, portability, arch). The repo's own runner infra (sh/Python3/TAP/TMSU) is
their CI only — bypass it; their per-compiler runners are 10-line `CC=x`
wrappers + a `.skip` script, nothing more.

1. Vendor https://github.com/c-testsuite/c-testsuite via the
   tools/install_lib_candidates.sh pattern (gitignored vendor source like
   sqlite/lua, PROVENANCE.md with upstream commit hash).
2. Write OUR OWN runner (tools/ script + `make test-c-conformance`): for each
   test, compile `./compiler/pascal26 -Ilib/crtl/include -Ilib/crtl/src NNN.c`,
   run with timeout, compare stdout+stderr against NNN.c.expected (byte-exact)
   and exit code 0. TAP output not needed; summary line pass/fail/skip.
3. Triage every failure: (a) cfront/codegen bug — reduce to minimal repro
   (compare vs gcc), fix or file per lane rules (shared internals = Track A
   ticket; as A/C combined you may self-resolve); (b) legit unsupported
   feature — add to an EXPLICIT skip-list file (mirror their `<name>.skip`
   idea) with one-line reason sourced from the test's .tags where possible.
   No silent skips. Bug fixes >> skips; skip only what is genuinely out of
   scope (e.g. features we have consciously deferred).
4. Gate: runner green (skips documented), make test + self-host byte-identical,
   test-lua-cross 24/24, sqlite suite still byte-identical vs same-version gcc
   oracle (oracle needs extra TU `const char sqlite3_version[]="3.46.0";` —
   see done/bug-c-create-trigger-huge-alloc-oom.md for why). If compiler bugs
   were fixed: make stabilize + make pin (watch pin.log — a stabilize flake
   makes pin silently re-bless the OLD binary; verify VERSION advanced).
5. Commit runner + skip-list + any fixes with regression tests; wire into make
   test only if fast (<~30s), else standalone target noted in this ticket.
   Update this ticket (step 1 done-notes), regenerate BOARD.md, push.

Steps 2 (zlib) and 3 (tcc) are separate sessions — do not start them unless
step 1 lands early and all gates are green.

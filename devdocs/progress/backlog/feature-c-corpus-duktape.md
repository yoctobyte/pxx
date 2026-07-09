---
prio: 55
---

# C corpus: Duktape — JS engine (GC + IEEE-754 corners)

- **Type:** feature (C frontend validation) — Track A/C.
- **Status:** backlog — planned 2026-07-09. Do AFTER [[feature-c-corpus-chess]].
  **COMPILES + RUNS JS 2026-07-09** (pinned v192). Four bring-up walls + the runtime
  segfault (32-bit pointer truncation, commit b30ccf88) all fixed. duktape now runs:
  integers/strings/arrays/JSON/closures/regex/recursion all correct. Remaining: JS number
  formatting is wrong (doubles scaled ~5^13) — [[bug-c-duktape-double-formatting]].
- **Parent:** [[feature-c-corpus-expansion]] (was roadmap item #5, promoted after tcc).

## Why Duktape
A small embeddable **ECMAScript (JS) engine** — exercises a class nothing else in the
corpus does: **garbage collection** (mark/sweep + refcount), **IEEE-754 double edge
semantics** (NaN/Inf, rounding, `%` on doubles, string<->number), tagged values, a
bytecode VM with big dispatch. Would have caught the v186 float-literal bug from another
angle. Real embedded C, portable C99, no computed-goto dependency (unlike QuickJS/
micropython, whose fast paths want `&&label`).

## Verified shape (do not re-derive)
- **Distributed as an AMALGAMATION** — `duktape.c` + `duktape.h` + `duk_config.h`
  (single-file core, the exact sqlite/tcc shape). Build the amalgam via its `tools/`
  (`make_dist.py` / `configure.py`) at fetch time with host python+gcc, then `pxx`
  compiles the resulting `duktape.c` + a small host (`duk_cmdline` or a minimal REPL).
- **Ships its own tests:** `tests/ecmascript/*.js` (hundreds of cases, each with an
  expected-output header), `tests/api/*.c`, and it can run **test262** (the official
  ECMAScript conformance suite). Oracle is built-in — run scripts, byte-compare stdout;
  NO gcc oracle needed for the JS-level tests (a gcc build of duk_cmdline is a cheap
  harness sanity cross-check).

## The plan (mirror tcc)
1. **Vendor** via `tools/install_lib_candidates.sh` (fetch pinned Duktape release,
   generate the amalgamation with host tools at fetch time, PROVENANCE.md w/ commit).
2. **Host + runner:** compile `duktape.c` + a minimal command-line (`duk_cmdline.c` or
   a ~50-line eval-file main) with `$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src`.
   `make test-duktape`: run a curated subset of `tests/ecmascript/*.js`, compare stdout
   to each test's expected block. Start with a smoke set (arithmetic, strings, arrays,
   closures, JSON), then widen.
3. **Blocker loop** (same as tcc): compile → run → cascade of cfront/crtl gaps. Expect
   crtl breadth gaps (math `*l`, `snprintf` corners, `setjmp`/`longjmp` — duktape uses
   long-jmp error handling like tcc did) interleaved with cfront/IR bugs. Reduce each to
   a minimal repro vs gcc, fix ONE, bXXX regression, land green. Float/GC bugs are the
   prize class.

## Gate
`make test-duktape` green on the curated JS subset (byte-exact stdout). Frontend/IR
changed → `make test` + self-host byte-identical → `make stabilize && make pin`. Cross
via Track T. Land green; regression tests per fix. Stretch goal: run a slice of test262.

## Landmines
Same as [[feature-c-corpus-chess]] (comment-brace, no ErrOutput, stabilize+pin verify).
Extra: duktape leans on `setjmp`/`longjmp` (crtl already has a shim from the tcc arc —
reuse it) and on double formatting (`%g`/`%.17g` round-trip) — validate string<->number
against gcc byte-for-byte early, it hides subtle float bugs.

## Recon log — 2026-07-09 (bring-up attempt, parked at wall #1)
- Vendored Duktape 2.7.0 prebuilt amalgamation (`duktape-2.7.0.tar.xz` → `src/duktape.c`
  101351 lines + `duktape.h` + `duk_config.h`; cmdline in `examples/cmdline/`). Not yet
  wired into `install_lib_candidates.sh` — deferred until unblocked (don't land a red gate).
- gcc oracle (17-case smoke: arith/float-fmt/NaN/Inf/mod/strings/arrays/closures/JSON/
  regex/Math.sqrt/GC-loop/recursion) builds + runs clean, exit 42. Float formatting exact
  (`0.30000000000000004`, `0.3333333333333333`, `1.4142135623730951`) — the prize class is
  reachable once the frontend gets past config.
- **Wall #1 (cfront, FIXED):** missing `__STDC_VERSION__` predefine → duktape never typedefs
  `duk_uintptr_t` (C99 `<inttypes.h>` gate) → cast parses as a call. Fixed by predefining
  `__STDC_VERSION__ 199901L` (+ `__STDC_HOSTED__`) in `cpreproc.inc`.
  [[bug-c-preproc-missing-stdc-version-predefine]].
- **Wall #2 (cfront, FIXED):** `duk_push_literal(thr, "Symbol(")` — the `(` inside the
  string literal corrupted function-like macro-arg matching (paren/comma scan ignored string
  literals). Fixed in `CPExpandRange`. [[bug-c-preproc-macro-arg-string-literal-paren]].
  After the fix duktape compiles ~13k lines further (to duktape.c ~28502).
- **Wall #3 (crtl, Track B, FIXED):** missing libc functions — `gmtime_r`/`localtime_r`,
  `strptime`, `gettimeofday` (time.c/h) and `cbrt` (math.c, was declared-not-defined).
  Commit 491a2b70.
- **Wall #4 (cfront, FIXED — the real blocker):** `while expected after do` surfacing at
  EOF. Root cause: `CPReadLine` spliced `\`<newline> only OUTSIDE comments, but C phase-2
  line-splicing precedes comment removal. A multi-line block comment whose lines end with
  `\` (every line of a block comment inside a `#define` body — duktape's
  `DUK__RZ_SUPPRESS_CHECK` refzero macros) was cut at the first comment newline, truncating
  the macro body and desyncing do/while brace matching. Fixed in `CPReadLine` (commit
  9aef018d). This was NOT a size/buffer bug — the ~55k-line truncation "threshold" was
  coincidental (the refzero helper lives at duktape.c:~54800). Regression b229.
  (Also hardened the unchecked `TokChars` pool writes → [[feature-c-compiler-dynarrays]].)

**RESULT:** duktape 2.7.0 compiles + links + heap-inits under pxx (pinned v191). Blocked on
a **runtime** segfault in the first `duk_peval_string` — [[bug-c-duktape-double-formatting]]
(setjmp/longjmp shim prime suspect). `make test-duktape` NOT wired yet (won't land a red
gate until the smoke runs green).

Regressions for the cfront fixes: `test/cpreproc_macro_arg_string_paren_b227.c`,
`test/cpreproc_stdc_version_predefine_b228.c`, `test/cpreproc_macro_comment_continuation_b229.c`
(all exit 42, wired into test-core).

[[feature-c-corpus-expansion]] · [[feature-c-corpus-chess]] · [[bug-c-preproc-missing-stdc-version-predefine]] · [[bug-c-preproc-macro-arg-string-literal-paren]] · [[bug-c-duktape-double-formatting]] · [[feature-c-compiler-dynarrays]] · [[feature-c-cmdline-define-flag]]

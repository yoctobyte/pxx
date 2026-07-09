---
prio: 55
---

# C corpus: Duktape — JS engine (GC + IEEE-754 corners)

- **Type:** feature (C frontend validation) — Track A/C.
- **Status:** backlog — planned 2026-07-09. Do AFTER [[feature-c-corpus-chess]].
  **PARKED 2026-07-09 at blocker #1** — see [[bug-c-preproc-missing-stdc-version-predefine]].
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
- **pxx build fails at blocker #1: missing `__STDC_VERSION__` predefine** → duktape never
  typedefs `duk_uintptr_t` (C99 `<inttypes.h>` gate) → cast parses as a call. Filed
  [[bug-c-preproc-missing-stdc-version-predefine]] (Track C). Per recon rule: analyzed +
  ticketed, no inline fix. Resume duktape once that lands (expect a cascade of further
  cfront/crtl walls behind it).

[[feature-c-corpus-expansion]] · [[feature-c-corpus-chess]] · [[bug-c-preproc-missing-stdc-version-predefine]]

---
prio: 50
---
# C corpus: bring up QuickJS — a real JS engine as a cfront target

- **Type:** feature (C frontend corpus). Track C.
- **Opened:** 2026-07-09 (user decision, from the JS-frontend advice session —
  see [[feature-js-frontend-parked]] for why this is THE JavaScript answer).
- **Depends on:** the zlib/tcc bring-up method ([[feature-c-corpus-tcc]], done).

## Goal — two birds

1. **Corpus:** QuickJS (quickjs-ng or Bellard upstream, ~85k lines of plain
   C99, single-threaded core, few dependencies) is the natural next
   real-world target after zlib/tcc — bigger, heavy on function pointers,
   unions, computed gotos (check: the interpreter loop may need
   `-DCONFIG_DIRECT_DISPATCH=0` style fallback to a switch), varargs,
   setjmp (crtl has it since the sqlite push), and long double printing
   (`js_dtoa` — watch the printf %g roundtrip ticket,
   [[bug-crtl-printf-g-double-roundtrip]]).
2. **JavaScript, delivered:** a compiled qjs binary IS full real JS on PXX —
   closures, prototypes, GC, async/await, eval, plus every pure-compute JS
   library — with zero JS-frontend work. This deliberately supersedes any
   native JS frontend (parked, see [[feature-js-frontend-parked]]): the
   engine route gets the actual semantics right because someone else
   already wrote the engine.

## Setup (mirror the tcc bring-up)

1. `fetch_quickjs` in tools/install_lib_candidates.sh — pin a release
   (quickjs-ng is the maintained fork; Bellard 2024-01-13 also fine),
   vendor under library_candidates/quickjs, gitignored, PROVENANCE.md.
2. Unity runner test/quickjs/runner.c over the core .c files (quickjs.c,
   libregexp.c, libunicode.c, cutils.c, quickjs-libc.c or a trimmed repl
   shim). Same unity-build macro-leak audit zlib/tcc needed.
3. `make test-quickjs`: gcc oracle vs pxx build; first bar = qjs evaluates
   `print(1+2)` → `3`; then a small pure-JS library file (e.g. a JSON or
   md5 implementation) run to an oracle-diffed result.

## Method (proven on zlib/tcc)

Diff → one mismatch = one bug → printf-instrument the vendored source →
minimal repro vs gcc → one compiler primitive → fix in cparser/ir/codegen
with a bXXX regression → self-host byte-identical → advance. Expect libc
surface gaps first (crtl math/stdio breadth), cfront corners second.

## Non-goals

- No DOM/HTML/WebGL — Cesium-class browser ecosystems are a browser, not a
  language; permanently out (same verdict as the parked JS ticket).
- No performance work (no direct-dispatch/computed-goto requirement; a
  switch-dispatch interpreter build is fine).
- No JS test262 conformance chase — "runs real pure-compute JS libraries"
  is the bar, not spec completeness.

## Gate

`make test-quickjs` advances; every compiler bug surfaced files as its own
Track C/A ticket with a minimal repro, same as zlib/tcc.

## Log

- 2026-07-12 (opus-night, setup + first walls) — quickjs-ng v0.9.0 imported
  (installer fetcher `quickjs`, pinned 670492dd, gitignored).
  `test/quickjs/runner.c` = unity build (cutils/libunicode/libregexp/libbf/
  quickjs.c) + a minimal embedder main; **gcc oracle green** (`1+2` -> 3,
  `[1,2,3].map(x=>x*x)` -> [1,4,9]). pxx walls knocked in order:
  1. **pthread once/cond missing in crtl** — added `pthread_once` (palsync
     RunOnce) + full condvar surface (`pthread_cond_init/destroy/signal/
     broadcast/wait/timedwait`, condattr accepted-and-ignored with the clock
     note) over palsync's seq-futex TCondVar; new `PalFutexWaitTimeout` +
     `CondWaitTimeout` in the PAL; `__pxx_pcond_*`/`__pxx_ponce` bridges in
     palpthread; ETIMEDOUT in crtl errno.h. NOTE: a bridge call passing two
     pointer-derefs to var params (`CondWait(c^, m^)`) trips "Mismatch in
     MatchProcCall" when palpthread is auto-pulled from a C compile (fine
     from Pascal) — bodies inlined in the bridge; parser quirk to minimise.
  2. **gcc bit-scan builtins** — cfront renames `__builtin_clz/ctz/
     popcount(+ll)` to `__pxx_builtin_*` crtl helpers (prototypes in crtl
     stdlib.h, loop bodies in stdlib.c). No intrinsic lowering yet.
  3. **C99 math gaps** — scalbn/isfinite/signbit/nan/remainder/expm1/log1p/
     acosh/asinh/atanh added to crtl math (bring-up accuracy; remainder does
     ties-to-even via fmod+parity).
  Regression: `test/cquickjs_prereq.c` in test-core (exit 42; gcc parity
  checked). Gate: 2-step self-host byte-identical, testmgr quick GREEN,
  ctcc/inet C smokes 42.
  ~~**NEXT WALL: `alloca`**~~ — LANDED 2026-07-14 night
  ([[feature-c-alloca-dynamic-stack]]): AN_ALLOCA/IR_ALLOCA, x86-64 grows the
  dynamic frame (16-aligned sub rsp; `leave` epilogue unwinds it), loop-called
  variable-size allocations gcc-parity (test/test_alloca.c). Other backends
  error cleanly until ported (QuickJS runs hosted x86-64).
  **NEXT WALL: `UINT64_C`** (libbf, quickjs unity build line ~18884):
  `call to undeclared function: UINT64_C` — the stdint.h constant macros
  (UINT64_C/INT64_C/UINT32_C/...) are missing from crtl's stdint.h. Track C/B
  (crtl header) — a few `#define UINT64_C(c) c##ULL` lines, needs cpreproc
  token-paste in that position.

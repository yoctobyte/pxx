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

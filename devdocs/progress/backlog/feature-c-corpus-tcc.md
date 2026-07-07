---
prio: 50
---
# C corpus: bring up tcc (TinyCC) as a real-world multi-file C target

- **Type:** feature (C frontend corpus). Track C.
- **Opened:** 2026-07-07, after zlib landed byte-identical to gcc.
- **Depends on:** the zlib bring-up method (feature-c-corpus-zlib, done).

## Goal
Compile a meaningful subset of TinyCC with pxx (libc-free, single-TU unity build)
and run it, diffing against a gcc oracle — the next real-world C project after
zlib. tcc is itself a C compiler, so "tcc compiles a hello.c" is a strong E2E bar.

## Setup (to do)
1. Add `fetch_tcc` to tools/install_lib_candidates.sh (github.com/TinyCC/tinycc,
   pin a release commit; vendor under library_candidates/tcc, gitignored like the
   others).
2. tcc needs a generated `config.h` / `tccdefs_.h` — either vendor a prebuilt one
   or generate with the host toolchain once; document in PROVENANCE.md.
3. Write test/tcc/runner.c that #includes the tcc core .c files as one TU (mirror
   test/zlib/runner.c), plus the crtl shims. Watch for the SAME unity-build macro
   leaks zlib hit — `#undef` any private macro that collides with a later file's
   identifier (zlib needed `#undef COPY`). Audit gzguts-style guardless headers.
4. Add `make test-tcc`: gcc oracle (compile tcc's own files separately) vs the
   pxx unity runner; start with tcc compiling a trivial hello.c and comparing the
   emitted output / exit.

## Method (proven on zlib)
test-tcc diff → each mismatch line = one bug → printf-instrument the vendored .c
(throwaway, restore after) → trace to the exact byte/value → minimal repro vs gcc
→ isolate to ONE compiler primitive → fix in cparser/ir/ir_codegen with a
regression (bXXX) → self-host byte-identical → drop/advance. Expect a cascade of
general cfront bugs (declarators, initializers, macro corners) like zlib surfaced.

## Gate
`make test-tcc` advances (tcc builds + runs a hello.c to a correct result); file
each compiler bug it surfaces as its own Track C/A ticket with a minimal repro.

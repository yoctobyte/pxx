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


## Started 2026-07-07 — fetch wired, first blocker found
- fetch_tcc added to tools/install_lib_candidates.sh (TCC_URL/COMMIT pinned to
  a338258d, TinyCC mob). Setup that works: `./configure` (config.h) + `make
  tccdefs_.h` (c2str.exe from conftest.c) — both run at fetch time with host gcc.
- pxx PARSES most of libtcc.c (the amalgam core, 10k+ lines) with
  `-Ilib/crtl/include -Ilib/crtl/src -Ilibrary_candidates/tcc`.
- FIRST BLOCKER: `libtcc.c:10545: call to undeclared function: __builtin_va_copy`.
  pxx supports __builtin_va_start/va_arg/va_end but not __builtin_va_copy (copy a
  va_list). Likely a small add mirroring the va_start handling in ParseCPrimary
  (cparser.inc). File as its own Track C ticket + minimal repro, then continue the
  parse to surface the next blockers (expect a cascade like zlib).
- NO runner/oracle yet: next is test/tcc/runner.c (unity include of the core .c)
  + make test-tcc (gcc oracle: tcc compiling a hello.c). Watch for unity macro
  leaks (#undef as needed, cf. zlib COPY).


## Blocker 2 (2026-07-07): libtcc.c:11810
After va_copy landed, parse advances to `:11810: unexpected token` near
`sizeof file  filename` — a sizeof/declarator corner (looks like `sizeof(<type>)`
where the operand tokenizes oddly, or an array-of-struct member). Reduce to a
minimal repro and file as its own Track C ticket; then continue the cascade.


## Blocker 3 (2026-07-07): libtcc.c:12370 — ldexpl (crtl/library gap)
After the unparenthesized-sizeof-field fix (b179), parse advances to
`:12370: call to undeclared function: ldexpl`. This is a LIBRARY gap, not a
cfront parse bug: `ldexpl` (ldexp for long double) is missing from lib/crtl math.
tcc uses long-double float parsing. Track B: add ldexpl (+ likely other *l
long-double math: strtold, etc.) to lib/crtl, or stub if long double is mapped to
double. File as a Track B crtl ticket. The cfront cascade is now hitting crtl
breadth gaps interleaved with parse bugs.


## Blocker 4 (2026-07-07): libtcc.c:14377 — codegen ICE IR_UNSUPPORTED
After the long-double aliases, parse advances to `:14377: Unsupported linear node
in IR codegen! Kind=10 node=47` (Kind 10 = IR_UNSUPPORTED). A C construct lowers
to IR_UNSUPPORTED — a C->IR lowering gap (Track C/A), deeper than the parse fixes.
Reduce: bisect libtcc.c around that token region to the construct, minimal repro,
file a Track C/A ticket. CLUE: the IR_UNSUPPORTED node has IRA=1 (=AN_INT_LIT),
IRB=-1, IRC=-1, IRIVal=0 — i.e. a childless integer-literal 0 reached codegen as
unsupported, which is odd (int literals always lower). Suspect a synthesized/
placeholder node from an unmodelled construct (tccgen.c IS in libtcc.c's TU and
uses computed goto `&&label` / `goto *` — a GCC extension pxx doesn't lower;
check if that's what emits the stray node). Needs instrumentation: print the
AST/IR node origin, or bisect the source region. (Progress: tcc parse went 10545
-> 11810 -> 12370 -> 14377 via 3 cfront fixes + crtl aliases; now at a codegen
lowering gap.)

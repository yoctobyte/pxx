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


## Blocker 5 (2026-07-07): libtcc.c:14395 — ELF64_ST_VISIBILITY undeclared
After the multi-declarator-global fix (b180), parse advances to
`:14395: call to undeclared function: ELF64_ST_VISIBILITY`. ELF64_ST_VISIBILITY is
a MACRO from <elf.h> (`#define ELF64_ST_VISIBILITY(o) ((o)&0x3)`). tcc uses its own
elf.h; pxx either doesn't find/parse it or the macro isn't defined in the TU, so
the call looks like an undeclared function. Check tcc's elf.h include + whether
pxx's cpreproc picked up the ELF*_ST_* function-like macros; IS bug-c-preproc-paste-rescan (NOT a new bug): `ELF64_ST_VISIBILITY` comes from
`ELFW(ST_VISIBILITY)(x)` where `ELFW(type)=ELF##64##_##type` (tcc.h:397) — the
paste result must rescan and consume the trailing `(x)`. So tcc's next blocker is
the parked paste-rescan rework (prio raised to 60). Progress:
tcc parse 10545 -> 11810 -> 12370 -> 14377 -> 14395 (4 cfront fixes + crtl aliases).

## MILESTONE 2026-07-07 (session 2): tcc COMPILES, LINKS, and RUNS `-v`
After paste-rescan landed (bug-c-preproc-paste-rescan done), one session cleared
blockers 6..N in a cascade; `compiler/pascal26 -Ilibrary_candidates/tcc
library_candidates/tcc/tcc.c out` now produces a 1.75MB binary that prints
`tcc version 0.9.28rc (x86_64 Linux)`. Fixes, in order hit:

cfront (cparser.inc, regression b184 covers all):
- :22215 `sizeof ((Stab_Sym*)0)->n_value` — postfix `->field`/`.field` after a
  parenthesized sizeof operand belongs to the operand (C 6.5.3).
- :29062 `TCCSem static rt_sem;` — storage class / qualifier AFTER the type name
  (static/extern/inline/volatile/register/restrict/_Noreturn accepted anywhere in
  the specifier run).
- :29139 `(tcc_enter_state(s1),_tcc_error_noabort)("...")` — comma expr yields
  the callee; CNodeProcSig recurses into AN_COMMA's right arm, callee stays the
  whole comma node so left-arm side effects run (AN_CALL_IND evaluates it).
- :29181 `int (*prog_main)(int,...), ret;` — sibling declarators after an inline
  fn-ptr declarator (fall through into the multi-declarator loop; sibling base =
  the fn-ptr's return specifier).
- :29232 `__pxx_setjmp(&(_tcc_setjmp(...)))` — `&(pointer-valued call)` (only our
  setjmp macro can produce it) yields the call value = glibc array-decay
  semantics. NOTE: proper fix is array typedefs (jmp_buf as `long[16]`) — typedef
  array dimension is LOST today (sizeof=8 not 128); file separately.
- :29264 `} while (++p, f);` — do-while condition is a full C expression
  (ParseCCommaExpr).

cpreproc.inc:
- `#undef` now kills ALL stacked entries of a name (repeated `#define _tcc_error
  use_tcc_error_noabort` from tcc.h's per-file re-include survived one tombstone
  and renamed the real `_tcc_error` DEFINITION → "undefined symbol: _tcc_error").

crtl/PAL (Track B files):
- getcwd: full chain — SYS_getcwd in all 5 posix arch tables + PalBackendGetcwd
  (+ ESP stub) + PalGetcwd + __pxx_getcwd + unistd.h/unistd.c veneer.
- unlink (rides __pxx_remove), fdopen + fileno (stdio), mprotect (no-op stub next
  to the stub mmap), realpath (identity copy, no symlink walk), execvp
  (link-only stub, ENOENT), assert.c (__pxx_assert_fail had NO impl anywhere),
  signal.h grown a POSIX surface (sigset_t/siginfo_t/stack_t/struct sigaction +
  sigemptyset/sigaddset/sigprocmask/sigaction/sigaltstack — bit-ops real,
  registration stubs) + crtl-own sys/ucontext.h (x86-64 glibc gregs layout;
  stops the /usr/include host-header leak).

## NEXT WALL: tcc -v works; `tcc_bin -c hello.c` SEGFAULTS
Runtime arc, not parse. Suspects, in order:
1. mmap/mprotect are stubs (mmap returns MAP_FAILED) — tcc_relocate needs real
   anonymous exec mappings. PAL has SYS_mmap already; bridge it (Track B) and
   make mprotect real.
2. struct jmp_buf passed BY VALUE where tcc treats jmp_buf as array→pointer
   (main_jb into _tcc_setjmp) — needs the array-typedef fix.
3. environ is referenced (`char **envp = environ;`) — resolved how? verify.
4. Any of the ~30 fresh crtl paths (fdopen etc.) or a genuine miscompile —
   instrument with the zlib printf-diff method once 1-3 are clean.

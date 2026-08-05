---
summary: "A crtl header that carries a BODY (stdarg.h's static __pxx_va_* helpers) is compiled twice — its include guard is invisible to the late crtl pull because a THIRD CPreprocess invocation in between clears the macro table"
type: bug
track: C
prio: 35
---

# A header carrying a body compiles twice across the macro-table reset

- **Type:** bug — Track C (C frontend, preprocessor TU state)
- **Status:** backlog
- **Opened:** 2026-08-05
- **Found by:** the C duplicate-definition warning, after
  [[bug-c-string-h-compiles-stdlib-c-twice]] was fixed. It is the last file in
  `test/*.c` that still warns (6 warnings, 1 of 373 files).

## Repro

```
compiler/pascal26 test/cvariadic_struct_b208.c -o /tmp/v
pascal26:46: warning: duplicate definition of '__pxx_va_start_impl' ...
pascal26:55: warning: duplicate definition of '__pxx_va_arg_gp' ...
pascal26:70: warning: duplicate definition of '__pxx_va_arg_fp' ...
pascal26:88: warning: duplicate definition of '__pxx_va_arg_cross' ...
pascal26:108: warning: duplicate definition of '__pxx_va_start_impl32' ...
pascal26:114: warning: duplicate definition of '__pxx_va_arg_cross32' ...
```

The file does `#include <stdarg.h>` and hand-declares `extern int printf(...)`.
The hand prototype makes `CPullCrtlForPrototypes` synthesise `#include
<stdio.h>` after pass 1; `stdio.h` includes `stdarg.h` again; `stdarg.h`'s
guard `PXX_CRTL_STDARG_H` is not visible there, so its six `static` helper
**bodies** are compiled a second time.

Benign today (the two bodies are identical, so it is wasted code, not a wrong
value) — but it is the same positional-binding hazard as the parent ticket, and
nothing checks that the copies stay identical.

## Root cause — measured, not reasoned

`CPreprocess` clears the macro table per invocation (right for Pascal's
unit-local `{$DEFINE}`, wrong for C's TU-global `#define`). A temporary trace
`writeln('INVOKE keepMacros=', ..., ' CPMCount=', CPMCount)` at the top of
`CPreprocess` shows **three** invocations for this one C program:

```
line      3: INVOKE keepMacros=FALSE CPMCount=0     <- the main TU; defines #22 PXX_CRTL_STDARG_H
line  99082: INVOKE keepMacros=FALSE CPMCount=27    <- a nested C file pulled by a PASCAL unit
line 102652: INVOKE keepMacros=TRUE  CPMCount=22    <- the late crtl pull; table already back to 22 predefines
line 102675: define #36 name=PXX_CRTL_STDARG_H      <- guard re-set => the body came through again
```

The middle one is the killer. It is `parser.inc:28977` — the Pascal
`uses`-a-C-file path — and it is a genuinely separate translation unit, so it
is *right* for it to reset the table. It just does so on the single global
macro table that the C program's own TU is still using.

**So carrying the macro table into the late pull is not sufficient on its own.**
That was tried (a `CPrepKeepMacros` flag around the `CPreprocess` call in
`CPullCrtlForPrototypes`, `cparser.inc:8138`) and measured to have no effect,
for exactly the reason above. It was reverted rather than left in as dead code.

## The fix

Save and restore the macro table around the **nested** invocation
(`parser.inc:28977`), then the `CPrepKeepMacros` carry works:

- The chain is newest-first and `#undef` only tombstones, so a snapshot of
  `CPMCount` + the whole `CPMHashHead[]` array (16384 ints, cheap) and a restore
  afterwards is an exact restore — entries `[0..savedCount)` and their
  `CPMHashNext` links are untouched by later appends.
- Known edge: a nested C file that `#undef`s a macro the outer TU defined
  tombstones `CPMNameLen` on the shared entry, and that is not undone by
  restoring the head array. Decide whether to snapshot `CPMNameLen` too or
  accept it.

`parser.inc` is shared Track A/P ground, so this is an A-gated change.

## Gate

`test/cvariadic_struct_b208.c` compiles with zero duplicate-definition
warnings; the whole `test/*.c` set stays silent; self-host fixedpoint.

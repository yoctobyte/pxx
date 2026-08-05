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


## ATTEMPTED 2026-08-05 — the prescribed fix is NOT sufficient; measured and reverted

The two-part fix above was implemented exactly as written and **does not fix the
bug**. Recording it so the next attempt does not repeat it.

Implemented:

1. `CPrepKeepMacros` flag; `CPreprocess` skips the table reset when it is set.
2. Save/restore of `CPMCount` + `CPMHashHead[]` **and** `CPMNameLen[0..saved)`
   around the nested Pascal-`uses`-a-C-file invocation (the `#undef` tombstone
   edge the ticket flagged — snapshotting the name lengths is cheap, bounded by
   the outer TU's macro count, so it was taken rather than accepted).
3. The flag set around `CPreprocess` in `CPullCrtlForPrototypes`.

**It works as designed and changes nothing that matters.** Trace at the top of
`CPreprocess`, this ticket's own instrument:

    CPPINVOKE keep=FALSE count=0     <- main TU
    CPPINVOKE keep=FALSE count=27    <- nested C file via a Pascal unit
    CPPINVOKE keep=TRUE  count=27    <- late crtl pull: WAS 22, now 27

So the carry is real — the third invocation now inherits the outer TU's 27
macros instead of resetting to the 22 predefines, which is precisely what the
ticket predicted would fix it. **The six duplicate-definition warnings are
unchanged**, and the file still builds and runs correctly (exit 42).

Therefore the guard's visibility is NOT the whole cause. Something else emits
`stdarg.h`'s bodies a second time — a candidate worth checking first is whether
the duplicate comes from the token stream rather than the preprocessor at all,
i.e. the already-expanded pass-1 text being re-parsed, in which case no amount
of macro-table carrying can help.

Reverted rather than left in: it is machinery with a measurable effect on the
macro table and no effect on the defect, and `testmgr --tier quick` stayed green
either way, so keeping it would only make the next diagnosis harder.

Still benign (the two bodies are identical) and still the last warning in the C
corpus: 5 of 369 files, of which 4 are the separate
`bug-c-static-functions-in-different-crtl-modules-collide`.

---
prio: 60  # raised: also blocks tcc (ELFW ## paste + rescan)
---

# C preprocessor: ## paste result must be rescanned for further macro expansion

- **Type:** bug (cpreproc). Track C.
- **Found:** 2026-07-06 c-testsuite run.

## Failing tests
- 00201: `#define CAT2(a,b) a##b` / `CAT(A,B)(x)` — paste yields `AB`, which is
  itself a function-like macro that must expand on rescan with `(x)`. Error:
  "call to undeclared function: AB".
- 00202: paste with EMPTY argument (`P(jim,)` → `jim##<empty>`) and pasting onto
  operators (`Q(+,)` → `+##<empty>+`). Error: "++/-- operand is not an lvalue"
  → `60 + +3` mis-lexed as `60 ++ 3`?

## Fix site
cpreproc.inc: after ## paste, re-run macro replacement over the result
(C99 6.10.3.3p3); empty-arg paste = operand disappears; paste output must be
re-tokenized as ONE token only if valid, else tokens stay separate (the `+ +`
case must NOT become `++`).

## Gate
Drop 00201.c/00202.c from test/c-conformance/pxx.skip; runner green.

## Triage note (2026-07-06)
Hard: needs macro RESCAN across the expansion boundary. `CAT(A,B)` pastes to the identifier `AB`, and the `(x)` that follows in the *source* must then be consumed so `AB(x)` expands. This is the same rescan machinery as CPObjectAliasFuncMacro but for a paste result feeding a following source arg-list — a rescan-loop rework in CPExpandRange, not a patch. Also 00202 needs empty-arg paste (`a##<empty>`) + pasting onto operators without forming `++`. Defer to a focused session.


## Triage 2026-07-07
The leveled expander (CPExpandRangeForLevel/CPExpandFunctionForLevel in
cpreproc.inc) does not rescan a function-macro's OUTPUT combined with trailing
SOURCE tokens. 00201 `CAT(A,B)(x)`: CAT(A,B) expands to token `AB`, then the
following `(x)` from source must re-scan `AB(x)` as a fresh function-macro call
(→ CAT(x,y) → xy → 42). "A macro expands to a function-like macro name that then
eats following tokens" is one of the hardest cpp corners — needs the expander to
feed its output back through scanning WITH the remaining input, not expand-in-
isolation. 00202 adds empty-arg paste (`P(jim,)`→`jim##<empty>`) and operator
paste that must NOT fuse (`60 + +3` ≠ `60 ++ 3`). Focused cpreproc rework. Parked.


## Also blocks tcc (2026-07-07)
tcc's `ELFW(type)` = `ELF##64##_##type` (tcc.h:397), used as
`ELFW(ST_VISIBILITY)(sym->st_other)` (tccelf.c) — pastes to `ELF64_ST_VISIBILITY`
which must RESCAN and apply to the trailing `(...)`. Same core as 00201
`CAT(A,B)(x)`. Fixing this unblocks tcc past libtcc.c:14395 AND drops 00201/00202
from pxx.skip. Raises the value of the paste-rescan rework — the macro output must
be fed back through scanning together with the remaining input, and a pasted
identifier that names a function-like macro must expand with the following args.


## Attempt 2026-07-07 — naive splice REGRESSES (reverted); fire-condition too broad
Tried a targeted splice in CPExpandRange (cpreproc.inc): after
CPExpandFunctionForLevel, if the level's temp output ENDS in a function-like macro
name and the next source token is `(`, append that `(...)` to the temp before the
rescan. RESULT: the single-level case works (`ELFW(ST_VISIBILITY)(7)`=3, tcc's
blocker), but it REGRESSED the gate — `make test` segfault, c-conformance 198->196,
lua fail. Reverted (gate restored to 198/0). Two concrete lessons for the real fix:
1. FIRE-CONDITION TOO BROAD: "temp ends in a func-macro name + next char is `(`"
   also matches legitimate cases where that trailing name is NOT being called
   (e.g. a macro passed as an object, or the `(` belongs to the surrounding
   expression), so it wrongly consumed the following `(...)` and corrupted
   expansion. Must only splice when the pasted/expanded name is genuinely in
   call position per C rescan rules, and must respect blue-paint.
2. MULTI-LEVEL: 00201 `CAT(A,B)(x)` still failed — CAT->CAT2->AB emerges the
   func-macro name only AFTER a nested rescan, so a check on CAT's IMMEDIATE temp
   ("CAT2(A,B)") misses it. The check must run on the FULLY-expanded output, i.e.
   capture the rescan result into a temp, test its tail, splice, and re-expand —
   not the per-level temp before rescan.
So the correct fix restructures the expand→rescan flow to (a) capture the full
expansion, (b) narrowly detect a trailing function-like macro in call position vs
the following source `(`, (c) splice + re-expand once. Focused cpreproc session
with the full gate as the guard (it does catch the regressions). Backup of the
attempt was discarded; re-derive from these notes.

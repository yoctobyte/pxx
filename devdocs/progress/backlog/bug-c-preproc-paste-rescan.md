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

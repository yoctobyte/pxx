---
prio: 55  # auto
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

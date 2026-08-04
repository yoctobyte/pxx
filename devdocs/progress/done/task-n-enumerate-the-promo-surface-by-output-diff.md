---
track: N
prio: 60
type: task
summary: "Before the int-promotion default can land, enumerate every site where a promotable int reaches a hand-built call or a static-type predicate — by DIFFING OUTPUT over a corpus, not by checking that programs compile"
status: done
owner: claude-AN
---

# Enumerate the promo surface by output-diff, not compile-success

Blocker for [[bug-nilpy-int-promotion-decided-statically-so-computed-overflow-wraps]],
whose cost question is now decided
([[decide-nilpy-int-promotion-costs-10x-on-ordinary-loops]]) but which cannot
land until this is done.

## Why it exists

That ticket's survey concluded "only `hex`, `bin` and `oct` break". It was wrong,
and the way it was wrong is the point: **it checked whether the program
compiled.** Re-run comparing OUTPUT against CPython, four more shapes were
silently wrong — `str(i+1)` and `round(i+1)` printed the slot address, `"ab" *
(i+1)` printed nothing, and `[0] * (i+1)` raised TypeError.

A compile-success survey cannot see any of those, and this frontend's whole risk
model is about silent wrong values. So the survey has to be redone properly.

## The shape every one of them has

A promotable int reaching either:

- a **hand-built call site** — `FindProc` returns ONE proc and never consults
  overloads ([[project_findproc_by_name_ignores_overloads]]), so the promo lands
  on a parameter that neither narrows nor boxes it and the SLOT ADDRESS is used
  as a value; or
- a **static-type predicate** — promo is deliberately not reported by
  `TypeIsOrdinal` / `TypeIsPyNumeric`, so a promo operand classifies as
  "unknown" and a path is chosen for it that assumes it is not a number.

Both are consequences of the rvalue model (`an rvalue is the SLOT ADDRESS`), and
both are invisible to a compile check.

## What to do

1. Apply the promotion patches (`devdocs/progress/patches/int-promotion-option1-*`).
2. Run a WIDE corpus — the `.npy` test suite is the obvious start, plus a
   generated probe over every builtin and operator against every operand shape —
   and **diff stdout against CPython**, not exit status.
3. For each divergence, add the arm: narrow at the call boundary, box to a
   variant, or teach the predicate about promo.
4. Re-run until the corpus is clean, THEN land the patches.

Note step 3 is not always a one-liner: adding promo to `IRPyOperandKind` was
tried for the `[0] * n` case and turned the TypeError into a garbage number, so
the list-repeat path has more than one thing in the way.

## Gate

The whole `.npy` suite diffing identical to CPython with the promotion patches
applied, plus the bug ticket's own table, plus a benchmark line recording the
measured cost so the 10x figure stays honest as check-elision lands.

## Log
- 2026-08-04 — resolved, commit b3ccf2f61.

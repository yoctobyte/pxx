---
slug: bug-a-nilpy-enumerate-over-str-inline-param-leak
title: enumerate() over a str trips an inline-placeholder leak (AN_INLINE_PARAM reaching IRLowerAST)
track: A
type: bug
prio: 35
status: open
---

## Summary

`compiler/pyparser.inc` REFUSES `enumerate()` over a string —
*"enumerate() over a str is not supported yet — enumerate(list(s)) works"* —
and its comment says an inline-placeholder leak (`AN_INLINE_PARAM` reaching
`IRLowerAST`) is the reason, *"filed separately rather than worked around here,
since a wrong lowering is worse than a clear refusal"*.

**It was not filed.** This ticket exists so that citation resolves.

## Status of the claim — read this before working it

The mechanism above is **quoted from the compiler comment and has NOT been
re-measured** (2026-09-11). I found it by grepping for comments that assert
paperwork exists, not by hitting the bug. What is certainly true is that the
refusal is live and the slug it names had no ticket file.

So the first step is **not** to fix the leak — it is to establish the leak is
still there. Remove the refusal at the `enumMode and (tyString or tyAnsiString)`
guard, rebuild, and run `for i, c in enumerate("abc")`. Two outcomes and they
want different work:

- it still leaks → the comment is accurate, fix the lowering, drop the refusal;
- it compiles and runs correctly → **the refusal is a stale guard**, which is
  the worse finding of the two: it has been refusing a valid construct for
  however long, and no test could have noticed because the refusal is the
  documented behaviour.

Do not close this by re-reading the comment. The comment is the thing under
test.

## Why it is only prio 35

`enumerate(list(s))` works and is the documented workaround, so no program is
blocked, only inconvenienced. Raise it if a real corpus wants the plain
spelling.

## Provenance

Found while correcting a DIFFERENT false "filed separately" in the same file
(`pyparser.inc:18397`, the arity guard —
`bug-n-a-method-call-is-refused-on-arity-from-the-candidates-compiled-so-far-so-import-order-decides`).
Census across `compiler/**` and `lib/**` that day: 33 comments claim paperwork,
21 name a resolvable slug, 12 name nothing checkable, and this was the one that
named a slug with no ticket behind it.

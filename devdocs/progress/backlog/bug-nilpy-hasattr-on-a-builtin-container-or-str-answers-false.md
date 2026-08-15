---
track: N
prio: 25
type: bug
blocked-by: []
summary: "`hasattr([1], \"append\")` / `hasattr({}, \"keys\")` / `hasattr(\"s\", \"upper\")` answer False for methods the very next line calls successfully. The predicate resolves user classes and the dynamic store; the builtin containers and str have no arm at all."
---

# `hasattr` on a builtin container or a str answers False

```python
print(hasattr([1], "append"), hasattr({}, "keys"), hasattr("s", "upper"))
# CPython: True True True
# pxx:     True False False        (pinned v317: False False False)
print([1, 2].count(1), {"k": 1}.get("k"), "s".upper())   # all three work
```

Found 2026-08-15 while resolving
[[bug-nilpy-getattr-dunder-not-supported]], whose test had to drop the row.
Pre-existing and unrelated to that dunder — the pinned compiler answers False
for all three, and the list arm only became True as a side effect of routing
`hasattr` through the wide predicate.

## Why it matters more than it looks

`hasattr` is Python's duck-typing primitive: `if hasattr(x, "read")` is how a
program decides whether something is file-like. Answering False about a method
that exists makes every such branch take the wrong arm — a silently wrong
answer, not a diagnostic, in code that is doing exactly what the language
recommends.

## Where

`pydynattr_has_any_v` / `pydynattr_hasattr` (pylib) resolve, in order: the
dynamic-attribute store, the declared fields, the user methods (RTTI), and
`__getattr__`. None of those know a `TPyList`, `TPyDict`, `TPyBytes`, a str, or
any other pylib-owned receiver, whose methods are frontend-resolved names rather
than RTTI entries — so the predicate has nothing to look in and says False.

`getattr(o, n)` on the same receivers is worth measuring at the same time: it is
the partner of this predicate and probably has the same hole.

## Shape of the fix

The names are known to the FRONTEND (that is how `[1,2].count(1)` resolves), so
the honest fix is one table the frontend and the runtime share, keyed by
receiver kind — not a second hand-written list in pylib that drifts from the
first. Check what `PyPylibMethodAlias` and the typed member-access table
already hold before adding anything.

## Gate

The three rows above plus `getattr` on the same receivers, diffed against
CPython, and a negative row (`hasattr([1], "nope")` → False) so the fix is not
"answer True for everything".

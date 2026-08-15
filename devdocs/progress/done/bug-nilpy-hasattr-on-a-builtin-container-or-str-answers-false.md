---
track: N
prio: 25
type: bug
blocked-by: []
summary: "`hasattr([1], \"append\")` / `hasattr({}, \"keys\")` / `hasattr(\"s\", \"upper\")` answer False for methods the very next line calls successfully. The predicate resolves user classes and the dynamic store; the builtin containers and str have no arm at all."
status: done
owner: agent-AN
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

## Resolution (2026-08-15)

The predicate was asking the wrong question, not missing a table.

`PyAttrFieldIdx` answers "is this a declared FIELD of a user class" — right for
building a field read, wrong for `hasattr`, because **a method is an attribute
too**. Everything else followed from that one substitution: a str method, an int
method, and a pylib container method reached under its Python ALIAS are all
attributes, and none of them is a field.

`PyAttrExists` is the wider question, and it reuses **the same tables the CALL
uses** — `FindUMeth`, `PyPylibMethodAlias`, `PyStrMethodInfo`,
`PyIsIntMethodBaseTk` + `PyIsIntMethodName` — rather than listing names again. A
second list is a second thing to keep in step, and the drift between the two is
exactly what this bug was. The ticket's own fix sketch asked for that and it is
what the frontend already had.

Only the hasattr ANSWER moved. `atFld` stays the field index because `getattr`
builds a field read out of it, and a method index there would be read as an
offset.

Two things measured rather than assumed:

- `PyIsIntMethodBaseTk` answers "may an int method claim this RECEIVER", which
  is true of ANY name on an int — a dispatch question, not an existence one. On
  its own it made `hasattr(1, "nope")` True. The name check
  (`PyIsIntMethodName`) has to be asked as well.
- The list arm was already partly right (`append`, `count`) because the runtime
  predicate finds pylib methods through RTTI. `d.keys` was False because the
  RTTI knows the PASCAL name and the user wrote the Python one — which is what
  makes the alias table the load-bearing part.

FPC seed: `PyPylibMethodAlias` is defined further down the same include, so it
needed a forward. `PyStrMethodInfo` and `PyIsIntMethodName` are above and did
not — the seed said so, and both extra forwards had to come back out.

### Gate

`test/test_nilpy_hasattr_builtin_receivers.npy`, byte-identical to CPython: the
three rows the ticket names, each receiver's surface positive AND negative (a
fix that answered True for everything would pass the headline row), the same
names still CALLING, `getattr`'s default still winning for a genuinely absent
name, and user classes — fields, methods, inherited, dynamic — unaffected. The
six attribute-related sibling tests re-run green.

### Not covered

`hasattr(1.5, "is_integer")` still answers False. Float methods are not
implemented at all ([[feature-nilpy-methods-on-int-and-float]], N p35):
`x.is_integer()` compiles and raises `TypeError` at run time, so answering True
would be a claim the call cannot honour. It becomes correct for free when that
feature lands, since this predicate reads that dispatch table.

`getattr` on a builtin receiver's METHOD (`getattr(l, "append")` as a bound
value) is also untouched — that is the method-as-value machinery, not this
predicate.

## Log
- 2026-08-15 — resolved, commit 16d5108c2.

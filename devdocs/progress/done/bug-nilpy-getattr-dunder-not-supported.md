---
prio: 30
track: N
type: bug
blocked-by: []
status: done
owner: agent-AN
---

# `__getattr__` (dynamic attribute fallback) is not supported

- **Type:** bug / missing protocol (NilPy) — **Track N**
- **Split out of** [[bug-nilpy-unsupported-protocols-repr-iter-getattr-delitem-hash]] 2026-08-09
- **Loud:** a compile error, not a wrong answer.

```python
class C:
    def __getattr__(self, name):
        return "GETATTR-" + name

print(C().missing_thing)    # CPython: GETATTR-missing_thing
```

```
pascal26:4: error: "missing_thing": no such member on this record/class
```

Re-measured at HEAD 2026-08-09: unchanged.

## Why this is the largest of the three siblings

Attribute lookup is resolved STATICALLY against the class layout, and the whole
point of `__getattr__` is to answer for names that are not in it. So the miss
has to become a runtime call rather than a compile error — which means the
compile-time "no such member" diagnostic can no longer fire for a class that
declares `__getattr__`, and every member-access site has to agree on that.

Note the existing `pydynattr_get`/`pydynattr_set` store: NilPy already has a
runtime attribute path for names it cannot resolve statically. Whether
`__getattr__` should be layered on top of that (dynattr miss → `__getattr__`)
is the design question to settle first, and CPython's own order is the answer to
match: instance dict, then class, then `__getattr__` last.

**Do not weaken the static diagnostic for classes that do NOT declare
`__getattr__`.** A typo'd attribute becoming a silent runtime miss is a much
worse trade than the feature is worth; the whole point is that the fallback is
opt-in per class.

`__setattr__`/`__delattr__` are the same family and should be scoped with it.

## Gate

`.npy` diffed against CPython: a class with `__getattr__` answering for a
missing name, a REAL attribute still winning over it, and the control that a
class WITHOUT `__getattr__` still gets the compile-time "no such member" error.

## Resolution (2026-08-15)

The ticket's own diagnosis was a session out of date, and re-measuring first is
what made this a small change instead of the frontend project it describes.
**`c.missing` already compiled** — the miss reaches `pydynattr_get` at run time,
which raised `AttributeError` rather than consulting the dunder. So most of the
work was in pylib, not in the resolver.

`PyUserObjGetattr` is the dispatcher, reading the call shape from the RTTI the
way the other dunder callers do: `__getattr__`'s name parameter is a str, but
the unannotated `def __getattr__(self, name)` types it as a Variant, so both
parameter shapes are dispatched and the return fans over the six RetKinds.
`PyUserObjGetattrTry` is the same call with an `AttributeError` refusal turned
into False, which is what a PRESENCE question needs — CPython defines `hasattr`
as "getattr does not raise", so a dunder that refuses some names has to be RUN
to answer it.

Wired at every place attribute lookup can miss, which was the real work:

- `pydynattr_get` (statically class-typed receiver) and `pydynattr_get_v`
  (variant receiver) — one concept, two receivers;
- `pyclsattr_inst_get`, a class-attribute read being an attribute read;
- `hasattr` / `getattr(o, n, dflt)`, which asked **store-only** predicates.
  Fixing that needed the predicate SPLIT rather than widened:
  `pydynattr_has` must stay store-only because `pydynattr_get` uses it to
  decide whether to fetch — widening it in place sent the getter to fetch a key
  that is not there and SEGFAULTED. The new `pydynattr_hasattr` is the wide
  question (store, declared, methods, `__getattr__`), the object twin of the
  existing `pydynattr_has_any_v`, and the two frontend sites now call the wide
  pair.
- `obj.name(args)` where no such method exists: lowered to the two Python steps
  written as one — the existing dynamic getter feeding the existing
  variant-callable call (`PyMakeDynCall`), so a proxy class gets the same
  dispatch that `g = obj.name; g()` already had.

### The sibling found on the way, and fixed with it

`D().missing` refused at COMPILE time (`"missing": no such member`) while
`d = D(); d.missing` resolved at run time — the receiver-shape split again
(member access has two parsers, and only the lvalue one knew). That is not
specific to `__getattr__`: `Plain().b` refused to compile where CPython raises
`AttributeError` at run time, so `try: obj.maybe / except AttributeError:` could
not even build for a call-result receiver. The chained-selector arm now routes
an unresolved member on a user class to the runtime getter for **any** NilPy
class, matching what the bare-identifier spelling always did.

### Cost accepted, stated rather than hidden

`getattr(o, n, default)` lowers to `has ? get : default`, so a class whose
`__getattr__` has SIDE EFFECTS sees two calls where CPython makes one. The
value is right either way. Collapsing it needs a single `pydynattr_get_or`
runtime entry and a lowering change; not done here.

### Not covered

`hasattr` on a builtin container or a str still answers False for a method it
plainly has (`hasattr([1], "append")`). Pre-existing — the pinned compiler says
False for all three — and unrelated to the dunder; filed as
[[bug-nilpy-hasattr-on-a-builtin-container-or-str-answers-false]].

Test: `test/test_nilpy_getattr_dunder.npy`, byte-identical to CPython — the
declared members winning, both receiver shapes, inheritance, hasattr/getattr
including a computed name, a dunder that refuses, a dunder returning a callable
and being called, and a class WITHOUT the dunder still raising. The eleven
attribute-related sibling tests re-run green.

## Log
- 2026-08-15 — resolved, commit 7473a64ab.

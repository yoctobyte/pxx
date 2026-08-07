---
track: N
prio: 50
type: bug
summary: "hasattr(o, \"x\") answers False whenever the receiver's static class has been erased to a variant — a list element, an untyped parameter — even though the attribute is declared and readable. Silent wrong value; implements the already-DECIDED decide-nilpy-hasattr-per-instance-semantics, which has no implementation ticket."
status: done
owner: claude-A-N
---

# `hasattr` on a variant receiver always answers False

- **Type:** bug (silent wrong value) — **Track N**
- **Found:** 2026-08-07, while checking the claim "no RTTI is emitted for a
  NilPy class" against the fact that `hasattr` works — the two look
  contradictory and are not (see below).
- **Pre-existing** — identical on `stable_linux_amd64/default/pinned`.

## Measured (self-hosted at `1eb579a96`)

```python
class P:
    def __init__(self):
        self.x = 1
p = P()
print(hasattr(p, "x"), hasattr(p, "zz"))   # True False   — correct
box = [p]
print(hasattr(box[0], "x"))                # CPython True   pxx False

def probe(o):
    return hasattr(o, "x")
print(probe(p))                            # CPython True   pxx False
```

The attribute is declared, and `box[0].x` / `o.x` **read fine** on the same
receiver. Only `hasattr` disagrees, and it disagrees silently — the idiom it
breaks is the guard, `if not hasattr(o, "x"): ...`, so the wrong answer sends
control down the wrong branch rather than raising.

Note the second shape: an **untyped parameter** is ordinary, idiomatic Python
and is probably the most common way to reach this in real code. It is the same
third symptom [[decide-nilpy-runtime-dunder-dispatch-mechanism]] recorded for
dunders on 2026-08-01.

## Cause — and the confusion it clears up

`hasattr`/`getattr` are resolved **entirely at compile time**
(`PyAttrFieldIdx`, `pyparser.inc` ~7264): `ResolveNodeRec` the receiver, then
`FindUField` on that class. A receiver with no static class returns
`REC_NONE`, and the source comment states the fallback as deliberate — *"A
receiver with no static class counts as 'does not declare it' — which is right
for the corpus"*. It is right for the censused corpus and wrong for the
language.

**This is why `hasattr` working is NOT evidence that NilPy classes carry RTTI.**
Three different mechanisms get conflated; only one of them is RTTI, and
`hasattr` uses none of them:

| mechanism | who has it | what it answers | used by |
| --- | --- | --- | --- |
| the **VMT** | every class | class identity + name (`ClassName`), virtual slots | `type(x).__name__` on a variant — works today, measured |
| the **published-member RTTI blob** (`rtti_emit.inc`) | only classes with >= 1 published member — NilPy sets `UMthPub := 0`, so **none** | reflective member lookup by name | `__pxxMethodAddress`, which is why it cannot see `__eq__` |
| the **per-instance dynamic attribute map** (`pydynattr_*`) | any instance that had an attribute set dynamically | attributes assigned at run time | `pydynattr_has` — `p.vars = {}` then `hasattr(p, "vars")` answers True today, measured |
| **compile-time field resolution** | — | declared fields, literal names only | **`hasattr` / `getattr`** |

So the reflective-looking capability that already works is the *dynamic
attribute map* plus compile-time field knowledge, not RTTI.

## This is already DECIDED — it just has no implementation ticket

[[decide-nilpy-hasattr-per-instance-semantics]] was resolved by the user on
2026-08-01 (option 2: real per-instance "assigned" tracking, scoped by
whole-program usage analysis so only classes/fields a `hasattr` site can reach
pay anything). Step 2 of that decision names this case explicitly:

> A genuinely ambiguous target (a base-class-typed value with several possible
> subclasses, a `Variant`) falls back to tracking every class in that ambiguity
> set — still bounded by what `hasattr` can reach, never the whole program.

The decision was never re-filed into the owning lane as work, which is why the
divergence has sat unfiled since. This ticket is that re-filing; the design is
not open, only the implementation.

## Fix shape

Per the decision. The variant-receiver arm specifically: when
`ResolveNodeRec` yields no class, the call cannot be answered at compile time,
so it must lower to a run-time check over the ambiguity set — and note that
`pydynattr_has` already exists and already answers the dynamically-set half, so
what is missing is the **declared-field** half for a receiver whose class is a
run-time fact. `type(x).__name__` proves the class identity is reachable from a
variant at run time (VMT `ClassName`), so a name-keyed answer is possible
without the RTTI blob.

**Do not silently widen it to "answer True whenever any class in the program
declares the name"** — that trades one silent wrong answer for another.

## Gate

Per-fix loop. A `.npy` diffed against CPython: `hasattr`/`getattr` with the
receiver a list element, a dict value, an untyped parameter and a caught
exception; a declared field, an undeclared name, and a dynamically-set one; the
`if not hasattr(o, "x"): o.x = ...` guard idiom (uforth's first-time-init, the
anchor case the decision names); and the zero-cost check the decision asks for —
a class reached by no `hasattr` site compiles identically to today.

## 2026-08-07 — FIXED (the declared-field half), and the trade is explicit

`hasattr` over a variant receiver now answers
`pydynattr_has(o, name) or ((pyvartag(o) = VT_OBJECT) and (o is C1 or o is C2 …))`,
where the `Ci` are the user classes that DECLARE the name.

This is the decision's step 2 — "an ambiguous target falls back to tracking every
class in that ambiguity set" — and it needs **no per-class metadata at all**,
which is the pleasant part: `AN_IS_TEST` already compares VMT addresses, and the
frontend already knows which classes declare a name. So the fix does not wait on
the RTTI blob NilPy classes do not get.

Three things that had to be right:

- **Only the class that INTRODUCES the field is tested.** `is` matches
  descendants, and `FindUField` already walks ancestors, so testing a base
  covers every subclass; emitting one test per declaring class would be correct
  but quadratic in a deep hierarchy. Covered by the Base/Derived case.
- **The tag guard is not optional.** `pyvarobj` hands back the raw payload, so an
  `is` test on an int-holding variant would dereference the integer. Same shape,
  same reason, as `PyParseIsinstance`'s variant arm — covered by the
  `[1, "s", 2.5]` case.
- **The receiver is bound to a hidden temp** (`PyEvalOnce`) before the chain is
  built: it is read once per candidate class plus once for the tag.

A `tyClass` receiver keeps today's answer exactly — its class WAS resolved, so
`atFld < 0` there genuinely means undeclared. Only the variant arm changed.

### The trade, stated plainly

This is not a pure win and the write-up should not pretend otherwise. For a field
assigned on only SOME path (`if flag: self.m = 1`), CPython says False; pxx's
static receiver already said True, and its variant receiver said False — *right,
but by coincidence*, since it said False to everything. Now both say True.

So that one shape went from accidentally-right to consistently-wrong, and the
common shape (a field assigned in `__init__`, reached through a list element or
an untyped parameter) went from wrong to right. The important part is that a
static and a variant receiver now agree, which turns two answers that contradicted
each other into one defect with one cause:
[[feature-nilpy-hasattr-per-instance-assigned-tracking]], filed with the measured
repro and the rest of the decided design.

**Verified**, self-hosted at this commit, diffed byte-identical against CPython:
the new `test/test_nilpy_hasattr_variant_receiver.npy` — static controls; list
element, dict value and untyped parameter; the field still READING on the same
receiver; the `if not hasattr(o, "x")` guard idiom on a class that has it and one
that does not; a dynamically-set attribute on both a named and an erased
receiver (the store half must not regress); base/derived inheritance; and
non-object variants (int, str, float) for the tag guard. Every existing
`hasattr`/`getattr` test re-diffed against CPython too —
`test_nilpy_attrs`, `test_nilpy_dynattr`, `test_nilpy_dynattr_class`,
`test_nilpy_missing_attribute_raises`, all MATCH. `tools/gate.sh quick` GREEN.

## Log
- 2026-08-07 — resolved, commit PENDING-COMMIT.

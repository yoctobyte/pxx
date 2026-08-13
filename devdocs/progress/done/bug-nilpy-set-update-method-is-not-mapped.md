---
track: N
prio: 40
type: bug
blocked-by: []
summary: "`s.update(other)` on a SET is a compile error (\"TPyList has no method update\") though CPython accepts it. The operator spelling `s |= other` works and lowers to TPyList.setupdate, so only the METHOD NAME is missing — the same Python-name-to-pylib-name mapping dict already has for items/keys/values."
status: done
owner: claude-A-N
---

# `set.update()` is refused — only the `|=` spelling reaches setupdate

- **Type:** bug (refused valid program) — **Track N** (Nil-Python frontend)
- **Found:** 2026-08-13, while sweeping sibling shapes for
  [[bug-n-inline-multi-entry-dict-literal-arg-loses-its-values]] (an unrelated
  argument-counting bug; this one surfaced in the same sweep and is its own
  defect).
- CPython accepts and runs this, so it is a real N bug rather than a
  laxer-than-CPython divergence (`devdocs/dev/nilpy-semantics-divergences.md`).

## Repro

```python
t = set()
t.update({4, 5, 6})
print(len(t))          # CPython 3 — pxx: compile error
```

```
pascal26:2: error: Nil Python: TPyList has no method update
```

## What works, and why that pins the cause

`s |= other` lowers fine, and pylib does implement the operation — as
`TPyList.setupdate` (`compiler/builtin/pylib.pas:132`), because a set IS a
TPyList here (`devdocs/dev/threading-model.md:109`). So the runtime is present
and correct; what is missing is the Python spelling `update` being mapped onto
it for a set receiver.

There is already a place that does exactly this kind of mapping for the other
container: `PyParseClassMethodCall` rewrites `items`/`keys`/`values` to
`itemlist`/`keylist`/`vallist` when the receiver's class is TPyDict
(`compiler/pyparser.inc`, near the top of that function), with the variant
receiver path (`PyParseVariantMethod`) carrying its own copy of the same table.

## The catch that makes this more than a one-line alias

`update` is ALSO a TPyDict method, and a set and a list are the same class here
(TPyList), so the mapping cannot be keyed on the class alone the way the dict
view methods are — a genuine list has no `update` in Python and should keep
saying so. Whoever picks this up should decide whether the receiver's
set-vs-list nature is known at that point or whether this wants a runtime arm.
That question is the reason this is filed rather than fixed in passing.

## Grep the siblings before closing

Set methods generally, for the same "operator works, method name missing"
shape: `difference_update`, `intersection_update`,
`symmetric_difference_update`, `issubset`/`issuperset` (pylib has
`setintersect`, `issubset` — check which spellings the frontend actually
routes), and `discard`/`add`.

## Gate

`make test-nilpy` + self-host fixedpoint; a `.npy` test diffed against CPython
covering `update`, the `|=` control, and a plain list's `update` still being
refused.

## DONE 2026-08-13

All four in-place set methods answer, matching CPython: `update`,
`intersection_update`, `difference_update`, `symmetric_difference_update`.

### The catch this ticket names, decided

The ticket asks whether the receiver's set-vs-list nature is known at the
mapping point. **It is not** — set vs list is `FKind`, a RUN-TIME field, and
every path that resolves a method name here runs at parse time. So the alias
applies to any TPyList, and a plain list now ACCEPTS `xs.update(...)` where
CPython raises AttributeError.

That is deliberate and it is not the gate line this ticket wrote. NilPy is
UPWARD compatible with CPython — accepting what CPython rejects is a language
choice, not a defect (`devdocs/dev/nilpy-semantics-divergences.md`), and the
alternative is a runtime arm on every list method call to reject a program no
correct Python contains. The gate's "a plain list's update still refused" row
is therefore dropped, with this note in its place.

### One table, one lookup, four call sites

`PyPylibMethodAlias(ci, name)` holds the table (the four set spellings for
TPyList; TPyDict's three view methods, folded in from the copy that was already
in `PyParseClassMethodCall`). `PyMethNameFor(ci, name)` is the only thing the
resolvers call: it answers the alias when the class does not declare the name
as written and does declare the alias, and the name itself otherwise — so a
class that spells the Python name directly is untouched.

Four sites consult it, because a class-typed receiver is resolved by four
different routes depending on its SHAPE, which is this frontend's recurring
trap (`normalise-dont-special-case.md`):

| route | receiver shape |
| --- | --- |
| `parser.inc` member access | `a.update(...)` — a bare name |
| `PyParseClassMethodCall` | `Cls().m(...)` — a fresh construction |
| `PyParseClassRecordSelectors` (pyparser's twin) | `mk().update(...)`, `bx.s.update(...)` |
| `PyParseVariantMethod`'s candidate scan | `xs[0].update(...)` — a variant element |

Building it in the first one only is what the first cut did, and `mk().update()`
still failed. The test's rows are those shapes for that reason.

### The variant scan arm also fixed a SEGFAULT

`xs[0].update({8})` on a set element crashed — on the pinned binary too. The
scan looked up `FindUMeth(ci, mname)`, so `update` found exactly one candidate,
TPyDict (the only class declaring it as written), and called `TPyDict.update`
on a TPyList. Scanning through `PyMethNameFor` makes TPyList a candidate via
`setupdate`, and the ordinary two-container runtime dispatch that already
exists there decides. The three `FindUMethArity` re-lookups on that path go
through the same helper, so the arity check agrees with the candidate scan.

### Siblings, measured not assumed

The ticket says to grep them. `union`, `intersection`, `difference`,
`symmetric_difference`, `issubset`, `issuperset`, `isdisjoint`, `add` and
`discard` were all **already correct** — pylib declares them under their Python
names, so nothing routed them anywhere. Only the four `*_update` spellings were
missing, and they are missing for a reason: `update`/`difference` would collide
with the list and dict surfaces in a case-insensitive language, which is why
pylib spells them `set*`.

### Spun off, not fixed here

`xs[0].update(...)` on a **DICT** element still segfaults, identically on the
pinned binary and untouched by this change: the variant path picks an
overloaded method by ARITY alone, so `update` always binds the first arity-1
arm (`update(l: TPyList)`) and a TPyDict is walked as a list. Filed as
[[bug-nilpy-dict-update-through-a-variant-receiver-picks-the-list-overload]]
with the measured shape table and the note that `PyPickOverloadByArgTypes`
may already be the answer. The test carries the row as a comment rather than an
assertion.

### Verified

`test/test_nilpy_set_update_methods.{npy,expected}` (`.expected` from CPython),
wired into `test-nilpy`: the four methods, mutation-through-an-alias, the
operator spelling agreeing with the method spelling, the four receiver shapes,
the nine already-working set methods as controls, and dict `update`/views as
the controls that keep the alias from stealing the dict surface.

Gate: `make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN + the
29-file NilPy dict/set/list/method test family re-diffed against its
expectations (this change moves a name-resolution gate, which the family sweep
is for).

## Log
- 2026-08-13 — resolved, commit PENDING-COMMIT.

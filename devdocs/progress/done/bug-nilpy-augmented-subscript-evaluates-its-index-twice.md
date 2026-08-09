---
track: N
prio: 30
type: bug
summary: "NilPy: `d[key()] += 1` calls key() TWICE — the augmented-subscript desugar re-evaluates the base and index. CPython evaluates each once. The stored value is correct; only a side-effecting index is observable."
---

# An augmented subscript evaluates its index twice

- **Type:** bug (semantic divergence) — **Track N**
- **Found:** 2026-08-06, while fixing
  [[bug-nilpy-augmented-assign-through-a-variant-subscript-is-dropped]].
  **Pre-existing on both subscript paths**, not introduced by that fix.

## Measured

```python
calls = []
def key():
    calls.append(1)
    return "n"

e = {"n": 0}
e[key()] += 1
print(e, len(calls))       # CPython {'n': 1} 1     pxx {'n': 1} 2
```

Same on a variant base (`d["a"][key()] += 1`). The **stored value is correct**
in every case — only the extra evaluation is observable.

## Why it is prio 30 and not higher

It is a deliberate, documented trade, not an oversight.
[[feature-nilpy-augmented-subscript-assign]] chose it when it made `d[k] += 1`
work at all: *"the index expression is evaluated twice, which is the same trade
the `del d[k]` rewrite makes and is invisible for the pure index expressions the
corpus uses."* That is still true — an index with side effects is rare, and a
NilPy program that hits this is unusual.

It is filed because "rare" is not "never", and because the reasoning above lives
in a resolved ticket where nobody will find it. A future reader measuring
`len(calls)` deserves to find this rather than re-derive it.

## Shape of a fix

Bind the base and the index to hidden temps once, then read and write through
them — the same thing `PyMakeVariantSetItem` already does for the *value*
(`__py_setval`, added for chained assignment). Both paths want it: the
default-indexed-property desugar in `parser.inc` and the variant arm beside it.

Do both together or neither, so the two spellings cannot drift apart — the last
two bugs in this family were exactly "one path was fixed and its sibling was
not".

## Gate

Per-fix loop. A `.npy` test counting calls to a side-effecting index function
under `+=` on a static base, a variant base, and `del`, diffed against CPython
with `tools/pydiff.py`.

## 2026-08-09 — re-measured, still open, PARKED on the sole-A guard

Confirmed current at HEAD, both paths, exactly as filed:

```
e[key()] += 1        CPython {'n': 1} 1   pxx {'n': 1} 2
d["a"][key2()] += 1  CPython 1            pxx 2
```

Not started, and not for lack of a plan — the ticket's "shape of a fix" is
right. Both desugars live in **`compiler/parser.inc`**: the
default-indexed-property arm and the variant arm beside it (~4864/4892). That is
Track A's shared file, and this session could not confirm it is sole-A (the user
was unavailable), so CLAUDE.md's cold-start rule applies: skip the shared-file
ticket, take a non-shared one.

Worth recording for whoever does pick it up: the two arms are ~30 lines apart in
the same function, so the ticket's "do both together or neither" is easy to obey
here — they are visible on one screen. The variant arm's own comment already
names the trade and points at the property arm, so both sites are self-documenting.

The `del d[k]` rewrite this ticket compares itself to has since moved on:
[[bug-nilpy-delitem-dunder-not-supported]] (2026-08-09) evaluates its key
exactly ONCE, by rewriting the node the grammar already built instead of
re-parsing it, and pins that with a side-effecting key. So `del` is no longer an
example of the same trade — it is a worked example of avoiding it, and the same
node-rewrite approach may apply here.

## 2026-08-09 — FIXED for the direct form (sole-A confirmed)

The base and the index are bound to hidden temps (`PyEvalOnce`) before the read
is built, so each is evaluated once. That also pins Python's evaluation order —
base, index, value — and makes the pre-existing index-chain CLONE harmless:
cloning an IDENT duplicates a read of a temp, not the expression behind it. The
clone itself has to stay; its own comment explains why (the setter appends its
value to that chain, and sharing it made the value an argument of the read, a
cycle that hung the compiler).

Verified against CPython for `+=`, `-=` and `*=` through a side-effecting index,
on a dict and on a list, plus the plain non-side-effecting forms and the
`counts[w] = counts.get(w, 0) + 1` counter idiom as controls.

**Every case COUNTS THE CALLS rather than checking the result** — the stored
value was always correct, so a test asserting `e == {"n": 1}` passes against the
broken compiler. That is the whole reason this bug survived.

## Residue: the NESTED form, unchanged from pinned

`g[ka()]["b"] += 1` still evaluates `ka()` twice. The outer subscript's base is
the INNER subscript's result and takes a different route to the augmented path.
Measured identical under `stable_linux_amd64/default/pinned`, so it is residue
rather than a regression, and it is deliberately not pinned by the new test.

Worth doing with the `parser.inc` carve-out
(`task-a-carve-nilpy-selectors-out-of-parser-inc`) rather than as another guard:
the chained and direct subscript paths disagreeing about evaluation order is the
same two-paths-one-concept shape that ticket exists to remove.

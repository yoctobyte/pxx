---
track: U
prio: 40
type: decide
blocked-by: []
summary: "A class with __eq__ and no __hash__ is unhashable in CPython, so `d[V(1)] = x` raises. NilPy stores it and then never finds it again — data in, nothing out, silently. Refuse the store (faithful), make content lookup work (friendlier, needs a __hash__ story), or document the divergence. The ticket that found it says explicitly to decide rather than guess."
---

# Object dict keys: refuse, support, or document?

Escalated from [[bug-nilpy-object-dict-key-with-eq-but-no-hash-is-accepted-then-misses]],
whose own closing line is *"If it is not obvious, file `decide-` rather than
guessing"*. It is not obvious, and here is the measurement that shows why.

## Measured today (2026-08-13)

| shape | pxx | CPython |
| --- | --- | --- |
| `d[k] = v` then `d.get(k)` — the SAME object | `"one"` | TypeError at the store |
| `d[V(1)] = v` then `d.get(V(1))` — equal but NEW | `MISSING` | TypeError at the store |
| `len(d)` after the store | `1` | — |
| a class with NO `__eq__`, same object | works | works (identity hash) |
| a class with NO `__eq__`, equal-but-new | `MISSING` | `MISSING` — agrees |

So the divergence is narrower than "object keys are broken": **identity-keyed
dicts work and match CPython.** What diverges is a class that defines `__eq__`,
where CPython refuses the store outright and NilPy accepts it and then answers
every read with the default.

## Why this is a dialect choice and not a bug fix

CPython's rule — defining `__eq__` sets `__hash__` to None — exists because two
objects that compare equal must hash equal, and the identity hash cannot
promise it. That is a real invariant of a hash table, not a historical
restriction, so the usual "PXX is laxer where the restriction was historic"
argument does **not** transfer for free.

But NilPy's dict is not purely a hash table: `TPyDict` probes an open-addressing
index when `FHashCap > 0` and falls back to a LINEAR SCAN over `PyVarEq` when it
is 0 — and `PyVarEq` already dispatches `__eq__` (that is what made `in`,
`count`, `index` and `remove` correct over a list of the same objects). So
content lookup is genuinely within reach here in a way it is not in CPython, and
that is the fact that makes this a choice.

## The options

1. **Refuse the store** — `d[obj] = v` is a TypeError when the class defines
   `__eq__` and not `__hash__`. Faithful; turns a silent miss into a diagnostic
   at the exact line. Cost: any NilPy program already using object keys starts
   failing, so the corpus needs a check first.
2. **Make content lookup work** — hash the key by `__hash__` when the class
   defines one, and otherwise force the linear-scan path so `PyVarEq` decides.
   Friendlier than CPython, allowed by the one-directional upward-compatibility
   rule, and plausibly small. Cost: a NilPy-only behaviour to document and keep
   working, and a performance cliff (a dict with such a key degrades to O(n))
   that is invisible until it bites.
3. **Document the divergence** — leave the behaviour, record it in
   `devdocs/dev/nilpy-semantics-divergences.md`. Cheapest, and wrong for the one
   thing that matters: the current behaviour is not laxness, it **loses data
   silently**, which no option should preserve.

Option 3 is listed only to be ruled out explicitly: whichever of 1 or 2 is
chosen, "stores and then never finds" must not survive the decision.

## Recommendation

**Option 2, with option 1's diagnostic as the fallback** where a `__hash__` is
declared but disagrees with `__eq__` — that is, make the common intent work and
refuse only what cannot be made to work. Measured support for it: the equality
route already exists and is already correct for lists, and the split where a
value object behaves correctly in a list and silently wrongly in a dict is what
reads as "dicts are broken" from application code.

## Gate (whichever is chosen)

The repro matching the chosen direction; identity-keyed dicts unchanged (they
match CPython today); `in`/`count`/`index` over a list of the same objects still
correct, since they share the equality route.

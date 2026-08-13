---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`c.update({\"x\": 5, \"y\": 0})` counts each KEY once and throws the values away (answers 1 1 where CPython answers 5 0). The SAME dict passed through a variable is correct, and a SINGLE-entry literal is correct — so it is the inline multi-entry `{...}` argument that is mislowered, most likely read as a set/iterable of keys rather than a mapping."
---

# An inline multi-entry dict literal passed as an argument loses its values

- **Type:** bug (silent wrong value) — **Track N** (Nil-Python frontend)
- **Found:** 2026-08-13, while writing the CPython-parity guard for
  [[bug-p-variant-to-int-and-char-conversion-diverges-from-fpc]].
- **Pre-existing** — reproduces identically on the PINNED compiler, so it is
  not from that change.
- CPython accepts and runs this, so it is a real N bug and not a
  laxer-than-CPython feature (`devdocs/dev/nilpy-semantics-divergences.md`).

```python
from collections import Counter

m = {"x": 5, "y": 0}
a = Counter(); a.update(m)
print("via var:", a["x"], a["y"])          # CPython 5 0 — pxx 5 0   OK

b = Counter(); b.update({"x": 5, "y": 0})
print("inline :", b["x"], b["y"])          # CPython 5 0 — pxx 1 1   WRONG

d = Counter(); d.update({"x": 5})
print("1 entry:", d["x"])                  # CPython 5 — pxx 5       OK
```

## The boundary, measured

Varying one dimension at a time — the counts below are `c["x"]` after the
update, CPython on the left:

| argument shape | CPython | pxx |
| --- | --- | --- |
| built in a loop, any size | 5 | 5 |
| named variable holding the dict | 5 | 5 |
| inline literal, ONE entry | 5 | 5 |
| inline literal, TWO+ entries | 5 | **1** (values dropped, each key +1) |

So it is neither the entry count as such (a loop-built 3-entry dict is fine)
nor `update` itself — it is specifically an inline `{...}` with 2+ entries in
ARGUMENT position. `1` is what you get from counting the KEYS, i.e. from
treating the literal as an iterable, which is exactly what `Counter.update`
does with a non-mapping.

## Where to look

Python's `{...}` is ambiguous between a dict display and a set display, and the
disambiguation is the `:`. A one-entry literal being right while a two-entry
one is wrong points at the ARGUMENT-position parse of the literal (a set-vs-dict
decision made on a token lookahead that only inspects the first element, or a
trial parse whose rewind loses the mapping shape — cf.
project_trial_parse_rewind_leaves_its_hoists_queued). Check what
`type()`/`len()` say about the argument as received, not what the call does
with it: `len(m)` is right for the variable form, so the object built OUTSIDE
the call is a proper dict.

Grep the sibling shapes before closing — an inline multi-entry dict literal
passed to any pylib routine that accepts "mapping OR iterable" is the same
question: `dict(...)`, `dict.update`, `Counter(...)`, `set(...)`, `**kwargs`
forwarding.

## Gate

`make test-nilpy` + self-host fixedpoint; a `.npy` test diffed against CPython
covering the four rows above.

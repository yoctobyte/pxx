---
prio: 60
track: N
type: bug
blocked-by: []
summary: "A NilPy local whose name equals its enclosing def's name aliases the function result instead of being an ordinary local: `def mode(label): tonic, mode = label.split(' '); return tonic, mode` returns ('C', None) where CPython returns ('C', 'minor'). Silent wrong value, no diagnostic."
status: new
owner: ""
---

# A local named after its own def aliases the function result

- **Type:** bug — Track N. Silent wrong value, no diagnostic anywhere.
  Filed 2026-08-30 by frankwasm, found while minimising
  [[bug-n-a-later-wall-in-key-analysis-blocks-convertrawtext-and-songformatter]].

## Repro

```python
# mod.py
def mode(label):
    tonic, mode = label.split(" ")
    return tonic, mode
```

```python
from mod import mode
print(mode("C minor"))
```

| | output |
| --- | --- |
| CPython | `('C', 'minor')` |
| pxx | `('C', None)` |

The local `mode` is never bound. Same shape with `label`:
`def label(label: str): ...` raises
`AttributeError: 'NoneType' object has no attribute 'split'` at run time —
the *parameter* is gone too.

## Why

In Pascal, assigning to a function's own name assigns its **result**. NilPy
inherits that resolution, so a Python local that happens to share the def's
name is not a local at all — it lands on the result slot.

This is a known family with a fixed sibling. `compiler/pyparser.inc` already
guards the case where the local is spelled `result`:

```pascal
    { NOT literally 'Result': Pascal's implicit result variable is case-insensitive,
      and `for result in detector_results:` is ordinary Python (songformatter's
      key_analysis writes it). Spelled that way, the loop variable RESOLVED to the
      function's result and the def returned the last element instead of what it
      computed. `return` targets RetSymIdx by index, never by name, so a name no
      Python source can spell keeps the two apart.
      See bug-nilpy-local-named-result-aliases-the-function-result. }
    idx := AllocVar('$pyresult', retType);
```

The `$pyresult` rename fixed the `result` spelling. **The def's own name is the
unfixed arm of the same defect** — and it is the more likely one in real code,
because nobody writes `result = ...` inside a function called `result`, while
`mode`, `label`, `value`, `item` are ordinary local names that a small helper
is also plausibly named after.

Related but distinct: [[bug-bare-function-name-call-vs-resultvar]] (done) is
the Pascal-side reading of a bare function name in an expression. This one is
about NilPy **assignment** to a name that is supposed to be a local.

## Why prio 60 and not lower

It is the silent-wrong-behaviour class from CLAUDE.md's compat table: real
Python that CPython accepts and runs, compiled without a diagnostic, producing
`None` where a value belongs. It needs no unusual construct — one small helper
whose name matches a local it computes.

## What a fix must assert

- a local matching the def name, plain assignment
- the same via tuple unpacking (the repro above — `mode` is one target of two,
  and the *other* target binds correctly, which is what makes it hard to spot)
- a **parameter** matching the def name (`def label(label)`), which currently
  loses the parameter
- a loop variable matching the def name (`for mode in ...` inside `def mode`)
- the existing `result` spelling, which must stay fixed

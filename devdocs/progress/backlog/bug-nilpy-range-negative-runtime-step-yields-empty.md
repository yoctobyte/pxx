---
track: N
prio: 55
type: bug
---

# `range(a, b, s)` with a NEGATIVE step passed at runtime yields an empty range

- **Type:** bug (NilPy, silent wrong value) — **Track N**
- **Found:** 2026-08-02, while fixing
  [[bug-nilpy-range-over-a-variant-bound-loops-forever]]. Distinct defect, same
  lowering.

## Measured

```python
def stepped(a, b, s):
    out = []
    for i in range(a, b, s):
        out.append(i)
    return out

print(stepped(10, 0, -3))     # CPython [10, 7, 4, 1]     pxx []
print(stepped(0, 10, 3))      # CPython [0, 3, 6, 9]      pxx [0, 3, 6, 9]  ok
for i in range(10, 0, -3):    # a literal step is fine
    ...
```

## Cause

The loop DIRECTION is decided at compile time, and only from a literal:

```pascal
if ((ASTKind[rngStep] = AN_INT_LIT) and (ASTIVal[rngStep] < 0)) then
  ASTIVal[cmpNode] := Ord(tkGt)
else
  ASTIVal[cmpNode] := Ord(tkLt);
```

So a step whose value is only known at run time always gets `<`, and a
descending range terminates immediately — empty, silently.

## Fix shape

Emit a RUNTIME direction test when the step is not a known-negative literal:
`if step < 0 then (i > stop) else (i < stop)`. The literal cases should keep
their current single-comparison lowering so nothing gets slower where the
direction IS known — which is the overwhelmingly common case.

Note this is the same "decided statically from a literal" shape as
[[bug-nilpy-int-promotion-decided-statically-so-computed-overflow-wraps]];
worth reading that ticket first, since a general answer may cover both.

## Gate

A `.npy` diffed against CPython covering: negative literal step, negative
runtime step, positive runtime step, a step of 0 (CPython raises ValueError),
and descending ranges that end exactly on the bound.

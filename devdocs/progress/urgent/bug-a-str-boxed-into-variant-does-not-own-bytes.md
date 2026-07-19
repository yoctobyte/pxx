---
track: A
prio: 80
type: bug
---

# A `str` boxed into a Variant does not OWN its bytes — silent wrong values

Found 2026-07-19 building [[feature-nilpy-dict]]; **not a dict bug** — the
smallest repro uses a list and no dict at all. Filed as Track A: the defect is
in the scalar->Variant boxing lowering (`IR_VAR_BOX` / `IR_VAR_ASSIGN` in
`ir_codegen.inc`), which is shared codegen, not frontend.

## Repro

```python
xs = []

def add(k: str) -> int:
    xs.append(k)
    return len(xs)

print(add("one"))
print(add("two"))
print(xs[0])
print(xs[1])
```

```
CPython:  1 2 one two
pxx:      1 2 two two      <-- both slots hold the LAST call's string
```

Silent. No error, no crash, plausible output.

## What is and is not affected

| boxed value | result |
| --- | --- |
| string LITERAL (`xs.append("p")`) | correct |
| module-level str local, reassigned between appends | correct |
| **str PARAMETER** | **aliases — every slot shows the last call's value** |
| a local COPIED from a str param (`t = k; xs.append(t)`) | **also aliases** |

That last row is the important one: the copy does not break the alias, so
"assign to a local first" is NOT a workaround, and the defect is in how a
tyString value becomes a variant payload rather than in parameter passing as
such.

## Second repro: a string LITERAL boxed inside a function

Same defect, no parameter involved — the payload has FRAME lifetime:

```python
from typing import Dict

class G:
    def __init__(self) -> None:
        self.m: Dict[str, int] = {}
    def fill(self) -> None:
        self.m["one"] = 1
        self.m["two"] = 2

g = G()
g.fill()
print(len(g.m))      # 2      correct
print(g.m["one"])    # 1      correct
print(g.m["two"])    # 1      WRONG (CPython: 2)
```

Read from INSIDE `fill` (before the frame dies) all three are correct — this
is a LIFETIME bug, not a store bug. The keys survive as far as their LENGTH
(different-length keys, and int keys, both behave correctly), so what is
retained is a pointer whose bytes are later reused; only same-length keys
collide, which is what makes the corruption so quiet.

## Reading of the cause (unconfirmed — verify before fixing)

`IR_VAR_ASSIGN` and `IR_VAR_BOX` both special-case the source kind:
`tyString -> EmitAnsiStrFromInlineString` (materialise a managed copy),
`tyAnsiString -> AnsiStrRetain`. The literal and module-local cases behave as
if the copy happens; the parameter case behaves as if the raw pointer is
stored instead. Suspect the frozen-string PARAM's "value" is the address of a
slot that itself holds a pointer, so the inline-string reader sees the wrong
shape — i.e. the same class of bug as
[[project_frozen_string_cross_backend_gap]], one level up.

## Why it matters now

Every NilPy container is variant-slotted, so this silently corrupts any
`list`/`dict` built from function or method arguments — which is most of what
[[feature-nilpy-corpus-uforth]] does. `feature-nilpy-dict` ships with its
`.npy` test trimmed around this bug; re-add the parameter-keyed case (a class
with `def put(self, k: str, v: int)`) when this is fixed.

## Gate

`make test` + self-host byte-identical (Track A), plus `test-nilpy` green and
the repro above matching CPython.

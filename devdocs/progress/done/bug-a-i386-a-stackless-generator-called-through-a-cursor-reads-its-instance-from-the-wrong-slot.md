---
track: A
prio: 50
type: bug
blocked-by: []
status: done
found-by: frankD (Nil Python cross-target differential, 2026-09-28: the test corpus built for i386, aarch64 and arm32 at -O2, diffed against x86-64 and CPython)
summary: "On i386 a Nil Python generator used through a CURSOR (`g = gen(4); next(g)`, `list(gen(3))`) yielded nothing or garbage. The step function takes only the instance pointer, but the for desugar pushed one pad per declared parameter and the cursor pushes one argument; with right-to-left pushes the callee read __genself from a pad or from the caller frame."
owner: ""
---

# i386: a stackless generator called through a cursor reads its instance from the wrong slot

```python
def gen(n):
    i = 0
    while i < n:
        yield i * 10
        i += 1
g = gen(4)
print(next(g), next(g))     # i386: empty or garbage; expected 0 10
print(list(gen(3)))         # i386: []; expected [0, 10, 20]
```

A `for` loop over the generator worked, which is the boundary.

## Mechanism

The step ABI is `function(__genself: Pointer): Boolean`; the declared parameters
live in instance slots. The `for` desugar still passes one pad per declared
parameter (the register targets pop ParamCount argument registers), and the
`pygen_iter_new` cursor calls the step through a pointer with ONE argument. On
register targets the two agree. On i386 the instance is pushed first, so it sits
deepest, and the callee's `[ebp+8]` held the last pad or the caller's frame.

## Fix

- `ir_codegen386.inc` IR_CALL: a call to a stackless proc pushes only the instance.
- `EmitParamSpillsForTarget` (i386): such a proc spills one parameter.

The pads are a zero literal or the instance variable, so dropping them leaves out
no evaluation that matters.

## Test

`test/test_nilpy_cross32_values.py` (first block), with a row in `test-i386`. Measured wrong with pin v446 (`stable_linux_amd64/default/stable_pinned`) on 2026-09-28.

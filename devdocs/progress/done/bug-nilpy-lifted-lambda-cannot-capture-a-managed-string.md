---
track: N
prio: 50
type: bug
status: done
summary: "A lifted lambda whose body reads an enclosing STRING local failed to compile with 'undefined variable' — the lift silently skips managed captures (a bound slot holds an Int64) and then emitted a body referencing a name not in its scope"
---

# A lifted lambda could not capture a managed string

- **Type:** bug (compile error on legal code) — **Track N**
- **Found + fixed:** 2026-08-10, by the test-family sweep while relanding
  [[bug-nilpy-every-lambda-is-interpreted-instead-of-compiled]].
- **Pre-existing**, confirmed on `pinned`.

## Measured

```python
def f():
    s = "hi"
    h = lambda x: len(s) + x     # body contains a call -> already lifted on pinned
    return h(1)
print(f())
```

    CPython: 3
    pinned:  error: undefined variable (s)

## Root cause

The lift's capture scan refuses managed strings on purpose — a bound slot holds
an `Int64`, and a borrowed string handle there would outlive its owner. But it
refused with a bare `Continue`, so the name was simply **not captured** and the
lifted body then referenced something not in its scope. The refusal was correct;
skipping quietly was not.

## Fix

Record the refusal (`lamManagedCap`) and **abandon the lift** for that lambda,
falling through to the pyeval closure — which captures by VALUE and handles the
shape correctly. Slower for those lambdas, and right, which is the correct trade
for a construct that otherwise does not compile.

Found because relanding the lift widening would have turned working closure code
(`lambda x: s + x`, no call, previously never lifted) into this compile error —
`test/test_nilpy_lifted_lambda_return_value.npy` covers exactly that shape.

## Note

The fix makes the lift REFUSE rather than teaching it to capture strings. The
better long-term answer is a bound-slot kind that owns a string reference
(`BK_VARSLOT` already exists for variants and would be the model), which would
let these lambdas compile AND run natively. Not done here: the refusal is the
small correct change, and the shape is rare enough that the closure fallback is
not worth a new ownership kind on its own.

Gate: the repro above matching CPython, `test_nilpy_lifted_lambda_return_value`
matching CPython, a 79-test family sweep green, `gate.sh quick` GREEN.

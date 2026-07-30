---
track: N
prio: 50
type: bug
---

# An int prints as `5.0` because the SAME NAME is assigned a float later in the file

```python
x = 5
print(x)          # CPython: 5      pxx: 5.0
x = 3.14
print(x)          # CPython: 3.14   pxx: 3.14
```

The first `print` runs before any float exists, and still renders `5.0`. A
later assignment retroactively changes how an earlier value is displayed.

Same inside a function body:

```python
def local() -> int:
    y = 7
    print(y)      # CPython: 7      pxx: 7.0
    y = 2.5
    print(y)
```

## How it was found, and why it survived

The suite's own `test/test_nilpy_widen_fix.npy` is exactly this program, and its
recorded expectation is pxx's output, not Python's:

```make
test "$$(/tmp/test_nilpy_widen_fix26)" = "$$(printf '5.0\n3.14\n7.0\n2.5')"
```

So the test passes while encoding the divergence — the same shape as
`test_nilpy_string_variant`, whose `x < a` expectation turned out to BE the bug.
Found by running all 230 `.npy` tests under CPython and diffing: 202 run
cleanly under CPython and only three diverge, this being the only genuine one
(one is a stdout-buffering artifact of the harness, one is the deliberate
`Optional[int] -> 0` sentinel).

## Cause

Rebinding a name across types widens its STATIC type to the join (int + float
-> float), which is what makes `x = 5` then `x = 3.14` legal at all — the name
has one slot. But the widened type is then used for every reference to the
name, including those lexically BEFORE the widening assignment, so the integer
is stored and rendered as a double.

CPython has no such constraint: a name is a reference, and each binding carries
its own type.

## Options

1. **Widen to VARIANT rather than to float.** The value then carries its own
   tag and renders per-binding, which is what the variant tier is for. Costs a
   boxed slot for any name that is rebound across numeric types.
2. **Split the binding.** Treat the pre-widening and post-widening regions as
   separate slots when the assignments are unambiguous — cheap where it
   applies, silent where it does not.
3. Accept and document. Weak: `5.0` for `5` is a wrong value in output, not
   just a representation nicety, and it appears in any script that reuses a
   loop or accumulator name for a float.

Recommendation: 1, since the variant path already exists and already renders
correctly for exactly this case (a value out of a heterogeneous container
prints correctly per element). Measure the cost before defaulting it on.

## Gate

`make test-nilpy` + self-host byte-identical. Note the expectation in the
Makefile for `test_nilpy_widen_fix` must be CORRECTED to CPython's
`5 / 3.14 / 7 / 2.5` as part of the fix — leaving it as-is would keep the bug
green.

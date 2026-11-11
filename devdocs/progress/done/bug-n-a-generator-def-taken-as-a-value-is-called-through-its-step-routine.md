---
track: N
prio: 50
type: bug
status: done
summary: "`gen = count; gen(3)` raised \"missing 1 required positional argument(s)\": a generator def's proc is its stackless STEP routine, whose first parameter is the instance, and a def taken as a value is called through its own code. Fixed: the value is the generator's FACTORY (PyGenFactoryFor), which now carries the generator's parameter names and defaults."
---

# A generator def taken as a value is called through its step routine

Found 2026-11-11 while fixing
[[bug-n-a-def-inside-a-taken-branch-does-not-rebind-the-name]], whose lowering
binds a conditional def through a callable value.

```python
def count(n, step=1):
    i = 0
    while i < n:
        yield i
        i += step
c = count
print(list(c(3)))      # CPython [0, 1, 2]; pxx: TypeError: missing 1 required positional argument(s)
```

`list(count(3))` was always fine: a direct call builds the cursor
(PyBuildGeneratorValue). Only the VALUE road (`c = count`, `run(count, 4)`,
`{"a": count}`) reached the step routine.

## Fix (pyparser.inc, rtti_emit.inc)

- PyMakeFuncValueFor, the one builder for a def in a value position, substitutes
  the generator's factory `$pygenmk_<gpi>`, the function a call above the def
  already uses. It skips captured or `*args` generators, which the factory does
  not take, and the typing pre-pass, which trial-parses statically dead arms
  whose generators never get a body (`if True: ... else: gen = _h` left an
  "unresolved forward").
- PyGenFactoryFor gives the factory the generator's own parameter NAMES (a
  keyword call binds by name) and copies every default carrier
  (ProcParamDefault*), so `c(3)` fills `step=1`.
- PySigDisplayName maps `$pygenmk_<gpi>` back to the generator's name, so
  `c.__name__` is `count`.

Test: test_nilpy_a_generator_def_as_a_value (row gensval26); latest-7020208c34
fails it.

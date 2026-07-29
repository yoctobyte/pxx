---
track: N
prio: 60
type: bug
---

# `print(x)` and `print(str(x))` disagree for a float

```python
print(str(1e19))   # 1e+19   — correct
print(1e19)        # 9223372036854775809.o72036854775808
```

Python has one float repr; pxx has two. `str()` goes through pylib's
`pystr_of` → `FloatToStr` (fixed in
[[bug-nilpy-large-float-str-overruns-into-garbage]] — it now handles NaN, ±Inf
and the past-Int64 range). `print` sends a float argument to the BACKEND
writer, `EmitWriteFloatNat`, which is hand-written per target and still
saturates, emitting a byte that is not a digit.

## Fix direction — one hook, not six backends

pyparser.inc, `PyParsePrint`, at

```pascal
      CurASTNode := PyReprContainer(CurASTNode);
```

Wrap a tyDouble/tySingle argument in the `pystr_of` Double overload right
there, exactly as the line above wraps a container in its repr. That routes
print through the same formatter `str()` uses, so:

- the garbage is fixed on every target at once, with no per-backend assembly;
- `print(x)` and `print(str(x))` agree by construction, which is the actual
  Python rule and is what makes this a bug rather than a formatting nit.

The container line is the precedent: `print` of a list already goes through
pylib rather than the backend writer for the same reason.

Note the argument node carries `ASTSOffset := -2` ("Python-natural float
format, EmitWriteFloatNat") — that marker becomes dead for floats once they
arrive as strings.

## Gate

`make test-nilpy` + self-host byte-identical, plus `print` vs `print(str(...))`
over 1e19, 1e300, 1e-20, 0.1+0.2, 2.5, -0.0, inf and nan, diffed against
CPython.

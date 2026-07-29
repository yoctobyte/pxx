---
track: N
prio: 65
type: bug
---

# Division by zero aborts the process and `except:` cannot catch it

```python
try:
    print(3 % 0)
except:
    print("caught")
print("after")
```

CPython prints `caught` then `after`. pxx prints
`Runtime error 200 (division by zero)` and exits 200 — the handler never runs
and the statement after the try block never executes.

`//` behaves the same. `/` is worse in a different way: it does not raise at
all, it prints garbage (see
[[bug-nilpy-large-float-str-overruns-into-garbage]]).

So the three division operators have three different behaviours for the same
input, and none of them is CPython's `ZeroDivisionError`.

The Pascal runtime's error 200 is being raised outside the NilPy exception
machinery, so the `try` frame never sees it. NilPy has working try/except
([[project_nilpy_exceptions_landed]]), so the fix is to raise a catchable
NilPy exception from the integer-division path rather than to let the runtime
trap escape.

Found by the operator × operand-type sweep against CPython.

## Gate

`make test-nilpy` + self-host byte-identical, plus a regression test that
catches `x % 0`, `x // 0` and `x / 0` and keeps running.

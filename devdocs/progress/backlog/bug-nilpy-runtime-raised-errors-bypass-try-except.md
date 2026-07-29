---
track: N
prio: 65
type: bug
---

# Runtime-raised errors bypass try/except entirely (division by zero, index, key)

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

## Not just division — every error the RUNTIME raises

The same sweep, extended to exceptions, found that NOTHING raised by the
runtime is catchable, while everything raised by user code is:

| program | CPython | pxx |
| --- | --- | --- |
| `x = [1]` … `x[5]` under bare `except:` | `bare caught` / `after` | `IndexError: list index out of range`, exit 1 |
| `d = {"a": 1}` … `d["zz"]` under `except KeyError:` | `caught key` / `after` | `KeyError`, exit 1 |
| same under bare `except:` | `bare caught` / `after` | `KeyError`, exit 1 |
| `raise IndexError("mine")` under `except IndexError:` | caught | **caught** — correct |

So the exception machinery works; the runtime's own error paths simply do not
go through it. They print a message and exit instead of unwinding to the
enclosing handler. Ordinary defensive Python — `try: v = d[k] except KeyError:`
— cannot be written at all.

That makes this one fix, not four: give the runtime error paths (index bound,
missing key, division by zero, and whatever else exits directly) a raise that
the NilPy `try` frame can see. The exception types already exist and already
match by name, as the `raise IndexError` row shows.

Everything else in the exception sweep matched CPython exactly: `raise` /
`except <Type>` / bare `except` / `except ... as e` / `finally` / `finally`
with a `return` in the try body / handler ordering.

Found by the operator × operand-type sweep against CPython, extended to
exceptions.

## Gate

`make test-nilpy` + self-host byte-identical, plus a regression test that
catches `x % 0`, `x // 0` and `x / 0` and keeps running.

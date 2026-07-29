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

[[bug-nilpy-int-parse-halts-instead-of-raising]] (opened 2026-07-27) is the
SAME defect seen through `int("abc")` — one more entry in the table, not a
separate bug. Fix them in one pass.

The mechanism is visible in `compiler/builtin/pylib.pas`:

```pascal
procedure PyIndexError;
begin
  writeln('IndexError: list index out of range');
  Halt(1);
end;
```

`PyKeyError` is the same three lines. Meanwhile the exception CLASSES are
already declared right there (`ValueError`, `TypeError`, `IndexError`,
`KeyError`, `OSError`, … all `class(Exception)`), pylib already raises
elsewhere (`raise Exception.Create('TypeError: ...')`), and a NilPy
`raise IndexError("mine")` is caught correctly. So the fix is to turn these
halt-helpers into raises of the class they already name.

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

## RESOLVED — the runtime raises instead of halting

Four halt sites in `compiler/builtin/pylib.pas` became raises of the classes
declared at the top of that same unit:

| was | now |
| --- | --- |
| `PyIndexError` — `writeln` + `Halt(1)` | `raise IndexError.Create('list index out of range')` |
| `PyKeyError` — `writeln` + `Halt(1)` | `raise KeyError.Create('key not found')` |
| `int("abc")` — `writeln` + `Halt(219)` | `raise ValueError.Create('invalid literal for int() with base 10: ' + quoted)` |
| `x // 0`, `x % 0` — bare Pascal `div`, trapping as runtime error 200 | `raise ZeroDivisionError` from `pyfloordiv_i` / `pyfloormod_i` / `pyfloordiv_f` |

`ZeroDivisionError` had no class at all and was added beside the others.

**True division needed more than a guard.** `3 / 0` was not trapping — it
produced a saturated Int64 that the large-float formatter printed as garbage
BYTES on stdout. Plain IEEE division can neither raise nor yield Python's
always-float result, so NilPy's `/` now routes through a new `pytruediv_f`.
That makes every NilPy division a call: a real cost, accepted because the
alternative is a silently wrong answer. Promotable-int operands stay on the old
path — their rvalue is a frame SLOT ADDRESS
([[project_promotable_int_stages123]]), so handing one to a Double parameter
would pass the address as a number.

**The first attempt at that routing was RED, and the gate caught it.** The arm
fired for every `/` in PyProgramMode, including `Path("a") / "b"` — pathlib's
join operator — which compiled a path handle as a Double and segfaulted
`test_nilpy_pathlib`. Both operands must be NUMBERS: `TypeIsPyNumeric`
(symtab.inc) now gates it, excluding tyClass, tyPointer, tyChar, tyVariant and
the string kinds, each of which has its own `/` meaning or none. Booleans are
in, since `True / 2` is 0.5 in Python.

Verified against CPython: `x % 0`, `x // 0`, `x / 0` and `int("abc")` each
caught by their own exception type and by a bare `except:`, with execution
continuing afterwards; message text matches CPython's for all four. Ordinary
division unaffected (`7/2`, `-7/2`, `7.5/2.5`, `10/5`, `//` and `%` over
int/float pairings all match).

This also closes [[bug-nilpy-int-parse-halts-instead-of-raising]].

## Two findings the fix exposed, filed separately

Both were invisible before, because the process died first:

- [[bug-nilpy-str-of-mixed-mod-prints-double-bits]] — `str(3 % 2.5)` prints the
  double's bit pattern. Parse-time typing of `%` ignores a float RIGHT operand,
  so `str()` binds the Int64 overload before ir.inc retypes the node.
- [[bug-nilpy-print-emits-arguments-before-evaluating-later-ones]] — `print`
  writes each argument as it goes, so a raise in a later argument leaves
  partial output.

### Gate

`tools/gate.sh full`.

## Log
- 2026-07-30 — resolved, commit e91ea31a0.

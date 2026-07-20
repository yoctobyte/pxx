---
track: A
prio: 80
type: bug
---

# NilPy `int("42")` returns a POINTER, silently — and `float()` does not exist

Found 2026-07-20 by sweeping NilPy's builtins against CPython.

```python
print(int(7))       # 7          correct
print(int(3.9))     # 3          correct
print(int("42"))    # 4281686    WRONG — CPython 42
x = "42"
print(int(x))       # 4287576    WRONG — same
print(float("2.5")) # error: undefined variable (float)
```

The string case is SILENT: a plausible integer, no diagnostic.

## Cause

`parser.inc:7956` lowers NilPy's `int()` to `AN_CALL` with `ASTIVal = -200`.
There is **no `cpi = -200` case in `ir.inc`** — only `-201` (`str()`) exists —
so the call falls through to a generic path that yields the argument's VALUE.
For a numeric argument that value is the integer, which is why the working
cases work; for a string it is the handle, printed as a number.

`float()` was never wired at all.

## Why the priority

`int(` appears 217 times in uforth.py and `float(` 3 times. Many of the
`int()` uses are numeric and therefore fine today, which is what makes the
string ones dangerous: the builtin looks like it works.

## Shape

Add the `-200` lowering beside `-201`, dispatching on the argument type:
numeric -> truncate (today's behaviour), string -> a real parse. The RTL
already has string-to-number conversion; `builtin.pas` has `StrInt` for the
other direction and `lib/rtl` has the parsing side. Decide what a
non-numeric string does — CPython raises ValueError; halting with a message
matches how NilPy handles IndexError and KeyError today.

`float()` is the same shape and should land with it: numeric -> widen,
string -> parse.

Both files are Track A, which is why this is filed rather than fixed under N.

## Gate

`make test` + self-host byte-identical, `test-nilpy` green, and all five
lines above matching CPython.

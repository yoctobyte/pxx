---
track: A
prio: 60
type: bug
---

# NilPy `str()` prints a string's POINTER and a bool's 1

Found 2026-07-19 building [[feature-nilpy-fstrings]].

```python
name = "bob"
print(str(name))    # CPython: bob     pxx: 4276256
print(str(5))       # CPython: 5       pxx: 5
print(str(True))    # CPython: True    pxx: 1
print(str(1.5))     # CPython: 1.5     pxx: 1.5
```

Both wrong cases are SILENT — plausible-looking output, no diagnostic.

`str()` on a class instance is the same shape: it prints the pointer as a
decimal number where CPython prints `<__main__.W object at 0x...>`. That one
cannot be diffed against CPython (the address varies), so it is not a
test-gate item — but it belongs to the same lowering, and uforth calls
`str(t).upper()` on an Any, so whatever this fix chooses for the object case
decides what that produces.

## Cause

`str()` is parsed in `parser.inc` (gated on `isNilPy`) into `AN_CALL` with
`ASTIVal = -201`, and lowered in `ir.inc` to one of StrInt / FloatToStr /
VariantToStr. The lowering has no case for `tyString` / `tyAnsiString` — the
argument falls through to StrInt and the string HANDLE is formatted as an
integer — and no case for `tyBoolean`, which reaches StrInt as 0/1 rather
than Python's `False`/`True`.

Both files are Track A, which is why this is filed rather than fixed under N.

## Shape

Add the two cases to the `cpi = -201` lowering: a string argument is already
the answer (identity), and a boolean picks the Python spelling. `pylib` now
has `pystr_of` overloads that do exactly this per type and could be reused as
the lowering target rather than growing the intrinsic.

## Note

[[feature-nilpy-fstrings]] does NOT wait for this: an f-string's whole job is
producing text, so the expander emits `pystr_of(...)` — argument type picks
the spelling through ordinary overload resolution — and f-strings are correct
today. Bare `str()` in user code is still wrong, which is this ticket.

## Gate

`make test` + self-host byte-identical, `test-nilpy` green, and the four
lines above matching CPython.

## Log
- 2026-07-20 — resolved, commit 62c4e457.

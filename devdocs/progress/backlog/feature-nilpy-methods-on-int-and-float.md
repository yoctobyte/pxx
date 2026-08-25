---
track: N
prio: 45
type: feature
---

# No methods on `int` or `float` — `x.bit_length()`, `x.is_integer()`, `x.hex()`

```python
x = 255
print(x.bit_length())      # error: Expected: ), but got: (Kind: 74)

y = 3.0
print(y.is_integer())      # same
print((3.5).is_integer())  # same
print((1.5).hex())         # same
```

Every method on a numeric value fails identically, so this is one gap rather
than several: a member access on an `int`/`float` is not recognised at all. The
failure is a parse error, so nothing computes a wrong answer.

`str`, `list`, `dict`, `set` and `bytes` all have their method surfaces (the
str one is now complete against CPython), which is what makes numbers the
outlier.

## What real code uses

In rough order of how often it turns up:

- `int.bit_length()` — the standard way to size a value
- `float.is_integer()` — "is this a whole number" without an epsilon dance
- `int.to_bytes(n, "big")` / `int.from_bytes(...)` — binary formats
- `float.hex()` / `float.fromhex()` — exact float round-tripping
- `int.as_integer_ratio()` / `float.as_integer_ratio()`

`is_integer()` and `bit_length()` are worth doing first and are trivial once the
member access resolves; the rest can follow behind the same mechanism.

## Note on the parse

The error names the DOT rather than the method, which says the receiver's type
is what rejects it, not the name — so the work is in the member-access path
recognising a numeric receiver, not in a method table. Whatever that path grows
should be reachable from BOTH a literal receiver (`(3.5).is_integer()`) and a
named one (`x.is_integer()`), which are different routes in this frontend and
are the classic place for one to be taught and the other not
(project_nilpy_lvalue_vs_selector_path_must_both_know).

## Gate

`make test-nilpy` + self-host byte-identical, with a CPython-diffed test over
each method from a literal receiver, a named receiver, an expression receiver
(`(a + b).bit_length()`) and a variant-typed one, plus the negative and zero
cases for `bit_length`.

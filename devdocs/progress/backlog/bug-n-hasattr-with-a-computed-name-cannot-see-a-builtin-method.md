---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`hasattr(x, n)` with the name in a VARIABLE answers False for every builtin-container, str, int and float method — `n = 'keys'; hasattr(a_dict, n)` is False while `hasattr(a_dict, 'keys')` is True. The literal and computed spellings of one question resolve through two different mechanisms and only the literal one was fixed."
---

# `hasattr` with a COMPUTED name cannot see a builtin method

Filed 2026-08-26 while resolving
[[bug-n-hasattr-through-an-untyped-parameter-is-always-false]] — measured, not
inferred, and deliberately NOT folded into that fix because the mechanism is a
different one.

## Measured (self-hosted at the fix's sha, and identical before it)

```python
def lit(x):
    return hasattr(x, 'keys')          # the LITERAL path
def comp(x, n):
    return hasattr(x, n)               # the COMPUTED path

d = {'a': 1}
print(lit(d), comp(d, 'keys'))         # CPython True True   pxx True False
print(lit('s'), comp('s', 'upper'))    # CPython False True  pxx False False
```

| receiver / name | CPython | literal path | computed path |
| --- | --- | --- | --- |
| `dict` / `keys` | True | **True** | **False** |
| `dict` / `values`, `items` | True | True | False |
| `str` / `upper`, `split`, `strip`, … | True | True | **False** |
| `int` / `bit_length`, `to_bytes` | True | True | **False** |
| `float` / `is_integer`, `hex` | True | True | **False** |
| `set` / `update` | True | True | False |
| `dict`/`list`/`tuple` / `__len__` | True | True | False |
| `list` / `append`, `count` | True | True | True |
| a user class field / method | True | True | True |

## Why the two paths differ

They are two mechanisms answering one question — the exact double case
`devdocs/dev/normalise-dont-special-case.md` is about, and the computed one is
the arm that stayed broken.

- **Literal name** → `pasparser_expr.inc` / `PyParseFactorCore`'s `hasattr` arm,
  which asks the FRONTEND's tables (`PyMethNameFor` / `PyPylibMethodAlias`,
  `PyStrMethodInfo`, `PyIsIntMethodName`, `PyIsFloatMethodName`) and, for a
  variant receiver, emits `PyHasAttrRuntimeChain` — run-time tag tests built
  from those same tables.
- **Computed name** → `PyMakeDynAttrByExpr` → pylib's `pydynattr_has_any_v`,
  which is pure run time: the dynamic store, `PyDeclaredAttrGet`,
  `PyPropertyGet`, `PyFindMethByName(GetInstanceRTTI(obj), …)`, `__getattr__`.
  It has no alias table (the RTTI knows `keylist`, the user wrote `keys`) and it
  `Exit`s outright when `pyvartag(v) <> 7`, so no scalar — str, int, float, bool
  — is ever consulted at all.

## Shape of the fix — and the reason it is a separate ticket

The frontend cannot answer a computed name, so this half has to be answered in
pylib, which means pylib needs what only the frontend has today: the
Python→Pascal method alias table and the str/int/float method name sets.
Hand-copying them into pylib is exactly the drift that
[[bug-nilpy-hasattr-on-a-builtin-container-or-str-answers-false]] was, so the
honest options are

1. **Emit the tables** — have the frontend lower a per-program table (or a
   generated `pyattr_exists_static(tag, name)` helper) that both paths consult,
   so the alias/str/int/float knowledge has exactly one author.
2. **Widen the RTTI** for pylib container classes so the Python spelling is
   findable at run time, and give `pydynattr_has_any_v` scalar-tag arms.

(1) keeps one source of truth and is the direction
[[bug-nilpy-hasattr-on-a-builtin-container-or-str-answers-false]]'s resolution
already argued for. Either way it is a pylib change, so it needs a pin to reach
Track B/E.

## Gate

The table above as a `.npy` with a CPython-generated `.expected`, each computed
row beside its literal sibling so the two arms disagreeing is what fails; plus
`getattr(x, n)` on the same receivers, which is this predicate's partner and
should be measured at the same time.

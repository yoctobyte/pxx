---
summary: "nilpy: d.values()/d.keys() jumped to address 0, and a local named `result` aliased the function result"
type: bug
track: N
prio: 75
---

# Three NilPy walls found in key_analysis.py

- **Type:** bug (Nil-Python frontend + pylib) — **Track N**
- **Found:** 2026-07-27. All three are ordinary Python that any real module hits.

## 1. `d.values()` / `d.keys()` called address 0

pylib names the dict views `keylist` / `vallist` (dodging the case-insensitive
clash with the default `Items[]` property), and only `items()` was mapped onto
its pylib name. `values` therefore resolved as an UNDECLARED attribute on a
class instance, which NilPy routes to `pydynattr_get` — and calling the None it
returns jumps to 0.

```python
ks = {"C": 3.0}
print(max(ks.values()))    # pxx: SIGSEGV (rip = 0)
```

Fixed in parser.inc, BEFORE the dynamic-attribute fallback, and in
`PyParseVariantMethod` for a variant receiver.

## 2. A local named `result` WAS the function's result

Pascal's implicit `Result` is case-insensitive, so `for result in xs:` bound the
loop variable to the function's result variable — the def then returned the last
element instead of what it computed (`TypeError: expected a number, got object`
when the caller used it as a float). NilPy's result variable is now allocated as
`$pyresult`, a name no Python source can spell; `return` targets it by index.

## 3. `len(<variant>)` did not compile, and float format specs halted

`len()` had no variant overload, so `len(x)` on a dynamically-typed value was a
compile error listing only the class and string candidates. And
`f"{score:.1f}"` halted with "format spec on a value of variant tag 3 is not
supported". Both are now implemented in pylib (`len(const v: Variant)`,
`pyformat_of(d: Double; spec)` with `.Nf` / `g`, plus int values under a float
spec, which Python prints as `2.0`).

## Gate

`test/test_nilpy_fnvalue_abi.npy` covers all three; `make test-nilpy`,
self-host byte-identical, `tools/gate.sh quick`.

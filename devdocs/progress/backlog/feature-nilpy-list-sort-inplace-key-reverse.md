---
track: N
prio: 30
type: feature
blocked-by: []
---

# `xs.sort(key=..., reverse=...)` — only the free function `sorted()` supports key/reverse

Found by proactive CPython-diff sweeping.

```python
data = [("a", 3), ("b", 1), ("c", 2)]
data.sort(key=lambda t: t[1])
print(data)
```
CPython sorts in place: `[('b', 1), ('c', 2), ('a', 3)]`. pxx: compile error —
```
pascal26:2: error: unexpected token
  near:   data  sort  >>> key  lambda
```

`sorted(l, key=..., reverse=...)` (the free function) already works —
implemented in `compiler/builtin/pyeval.pas`, NOT `pylib.pas`, specifically
because invoking the `key` CALLABLE needs pyeval's closure-dispatch machinery
(`pycall_value`/`PyCallKey1`-style dispatch mentioned in that file's own
comments). `TPyList.sort` (the in-place instance method, declared on
`TPyList` in `compiler/builtin/pylib.pas`) only has the bare `function sort:
TPyList;` overload — no `key`/`reverse` params — because `pylib.pas` is
loaded (and `uses`d) BEFORE `pyeval.pas`, so it has no visibility into the
callable-dispatch machinery a `key=` implementation needs.

## Fix direction

Since `TPyList` can't gain a same-named overload from a LATER unit (Pascal
doesn't reopen a class across units the way a class helper elsewhere might),
the natural fix mirrors how the free function already exists: add a plain
function in `pyeval.pas` — e.g. `pylist_sort_inplace(l: TPyList; key:
Pointer; reverse: Boolean)` — that calls the SAME sort logic `sorted()` uses
but writes the result back into `l` in place (clear + refill, or an in-place
swap-based sort) rather than returning a new list. Then wire
`xs.sort(key=..., reverse=...)` in the frontend (`compiler/pyparser.inc`'s
method-call dispatch) to recognize this specific method+kwarg shape and call
that free function instead of the bare `TPyList.sort` method — the same
"method call dispatches to a free pylib function" pattern already used
elsewhere in this frontend (e.g. `str` methods route through
`PyParseStrMethod` to plain `pystr_*` functions, not genuine `AnsiString`
methods).

Not attempted this pass — needs a new parser dispatch branch plus a
pyeval.pas addition, more scope than a quick patch mid-sweep; the plain
`xs.sort()` (no key) and `sorted(xs, key=..., reverse=...)` both already
work, so this is specifically the in-place-method + key/reverse combination.

## Gate

A `.npy` case with `.sort()`, `.sort(reverse=True)`, `.sort(key=lambda...)`,
and `.sort(key=..., reverse=True)`, diffed against CPython (checking the
mutation is genuinely in place, not just a return value), gated in
`test-nilpy` + `--tier quick` + self-host byte-identical.

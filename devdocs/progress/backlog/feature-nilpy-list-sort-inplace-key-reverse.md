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

## 2026-08-15 — the premise is half-outdated; the wall is the CALLABLE SHAPES, not the unit

Re-measured before starting, and two of the three things above have changed:

- **`reverse=` already works.** `TPyList.sort(reverse: Boolean = False)` exists
  in pylib and `xs.sort(reverse=True)` compiles and sorts. Only `key=` is
  missing, so the title overstates the gap.
- **pylib is not blind to callables.** It has `pyvar_callable_ptr` /
  `pyvar_callee_addr` (a callable VARIANT to a raw code pointer), plus
  `pyboundfn_callv` and the bound-pair helpers. So "pylib cannot call a key"
  is no longer true in general, and an in-pylib `sort(const key: Variant)`
  overload — which the keyword binder would resolve with no frontend change at
  all — looked like the cheap answer.

**Why that cheap answer is still wrong.** `PyCallKey1` dispatches FOUR callable
shapes (bound pair, pyeval source closure, pyboundfn, bare code address). Three
of them are reachable from pylib; the **source closure is pyeval's**, and it is
the fallback for every lambda the lifter refuses. A pylib-side `sort` would
therefore work for most `key=lambda ...` and mis-handle exactly the ones that
fall back — a per-lambda-shape failure, which is worse than the current loud
"has no parameter named 'key'".

So the ticket's own fix direction stands: **the sort with a key belongs in
pyeval**, beside `sorted`, which already has all of it. What it costs is the
frontend wiring the ticket names, and that is the real work:
`xs.sort(...)` is parsed by the ARITY-DRIVEN method-call loops in `parser.inc`
(there are several — the local-receiver one and the field-receiver one at
least), so redirecting one method name to a free function needs a hook each
place, or a shared "list method that is really a free function" table of the
kind `PyStrMethodInfo` already is for strings. That table is the right shape
and does not exist yet for lists.

Nothing applied. Measured with the v327 self-host at HEAD.

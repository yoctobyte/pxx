---
track: N
prio: 62
type: feature
blocked-by: []
status: done
owner: frankwasm
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

## 2026-08-30 — DONE. Both stated blockers were outdated; the real one was a third thing

Landed. `xs.sort(key=..., reverse=...)` now matches CPython for every callable
shape and every receiver. Two corrections to the analysis above, and one finding
neither pass had.

**The 2026-08-15 objection is dissolved, not worked around.** It said a
pylib-side `sort` must mis-handle the callable shapes that fall back to pyeval's
source closure, so the sort had to move to pyeval. That was true when written and
is not now: pyeval installs `PyCallKey1` into **`PyIterCallHook`** (declared
`pylib.pas:151`, used at `:1378`) precisely to invert this dependency — map/filter
cursors in pylib had the identical problem. Its own declaration comment names it
"the one entry point that knows all four callable representations". So a key
invoked through the hook goes through the *same* dispatcher `sorted()` uses, and
there is no shape that can diverge between the two — which was the entire
objection. `TPyList.sort` gained `key: Pointer = nil` and calls it; nothing moved
to pyeval, and no "list method that is really a free function" table was needed.

**The `parser.inc` reference was stale** — that file is now the `pasparser_*.inc`
set (2026-08-20). Left as written above; this note is the correction.

**What actually blocked it was neither.** Declaring the parameter was ~20 lines.
The wall was that the frontend never coerced the callable into the raw `Pointer`
the slot wants. A callable VALUE is a 16-byte variant, and the plain coercion
takes its first word — the **tag** — as a code address, so the program jumps to
8, 9, 10 or 12. `sorted()` was immune only because the plain-call path had that
coercion inline. Measured, `sorted(xs, key=K)` vs `xs.sort(key=K)` at the same
HEAD:

| K | `sorted()` | `.sort()` before |
| --- | --- | --- |
| inline `lambda` | ok | ok (lowers to a proc address already) |
| `len` | ok | **SIGSEGV** |
| `str` (a builtin TYPE) | ok | **SIGSEGV** |
| a named `def` | ok | **SIGSEGV** |
| a bound method | ok | **SIGSEGV** |
| a lambda held in a name | ok | **SIGSEGV** |

Five of six. That is exactly the "works for most `key=lambda ...` and mis-handles
the ones that fall back" failure the 2026-08-15 note predicted — it just came
from the frontend rather than from pylib, so moving the sort to pyeval would not
have prevented a single row of it.

**The fix, and why it is one line in one place rather than seven.** The inline
coercion was extracted from the plain-call path into `PyCoerceCallableArgsIn`
(`pyparser.inc`), which also absorbs the builtin-TYPE rewrite (`key=str`, whose
payload is a small code, not an address) now that the resolved parameter can
answer that question exactly. Wiring it into the method loop I first found made
a local and a field receiver work while `nested[0].sort(key=f)` still
segfaulted: there are **seven** arity-driven argument loops (local, field,
indexed, dynamic, star-unpack, collect, class-method), spread across files two
tracks own, and each is a separate road to the same construct. They all funnel
through **`PyBindKwArgs`**, so the coercion goes there, after its reorder — one
site, every loop, and no Track A/P file touched. `devdocs/dev/normalise-dont-special-case.md`.

Gate rows in `test/test_nilpy_list_sort_key.npy` (expectation generated from
CPython, `diff -u`, negative-control checked that it is load-bearing): the six
callable shapes, `key=None`, a capturing lambda and a closure returned from a
def, four receivers, `key=` with `reverse=` in both keyword orders, the plain
`.sort()`/`.sort(reverse=True)` forms, stability in **both** directions, the key
being called exactly once per element, in-place identity and the `None` return.
Full file diffs clean against CPython. `test_nilpy_list_sort_method`,
`test_nilpy_sort_lt_dunder` and `test_nilpy_list_mutators_return_none` still
match CPython.

Files: `compiler/builtin/pylib.pas` (the `key` parameter and the lockstep key
list), `compiler/pyparser.inc` (`PyCoerceCallableArgsIn` + the `PyBindKwArgs`
call, and the plain-call path now delegating instead of carrying its own copy),
`compiler/pyforwards.inc` (forward).

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.

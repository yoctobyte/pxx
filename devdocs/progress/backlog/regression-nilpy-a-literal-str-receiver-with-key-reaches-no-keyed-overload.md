---
prio: 50
track: N
status: backlog
owner:
---

# regression: a LITERAL str receiver with `key=` reaches no keyed overload

Split out of `regression-test-nilpy-test-nilpy-max-min-iterables`, which fixed the
dict and named-str arms in the library. This arm needs the frontend.

## Measured

Same commit as that regression — `7b73a385d` (the callable→Pointer coercion moved
into `PyBindKwArgs`). At `7b73a385d^` the literal form printed `b`.

```python
def f(k): return len(k)
print(max("bca", key=f))     # LITERAL  -> TypeError: '>' not supported between 'int' and 'str'
s = "bca"
print(max(s, key=f))         # NAMED    -> b        (fixed by the AnsiString overload)
print(max(("b","a"), key=f)) # LITERAL tuple -> compile error, see below
t = ("b","a")
print(max(t, key=f))         # NAMED    -> b        (already worked at 7b73a385d^)
```

Regressed: **literal str**. Pre-existing (fails at `7b73a385d^` too, so NOT part
of that regression): **literal tuple / inline generator expression**, which is
`bug-nilpy-keyword-arg-vs-overload-set` and reports

```
max has no parameter named 'key' in the overload taking 2 argument(s) —
a sibling overload taking 2 does.
```

## Why the library fix does not reach it

`min`/`max` now carry `TPyDict` and `AnsiString` keyed receivers, mirroring
`sorted`. A NAMED str binds to the `AnsiString` overload; a LITERAL does not — the
keyword promoter re-targets on the argument's **static type** (see the comment
above `min(l: TPyList; key…)` in `compiler/builtin/pyeval.pas`: "`min` is picked
from pylib's two-Variant scalar form, and the keyword `key` is what re-targets it
here"). So the literal never becomes a candidate for any keyed overload, and
adding more library overloads cannot fix it — including a `Variant` keyed pair,
which I wrote, measured as buying nothing, and removed.

Fix belongs in `compiler/pyparser.inc` (Track N), alongside
`bug-nilpy-keyword-arg-vs-overload-set` — plausibly the same change, since both
are the promoter choosing by static type before the keyword is considered.

## Guard

`test/test_nilpy_max_min_iterables.npy` covers the named receivers and says in its
header that literals are deliberately absent — do not read it as covering them.
Add the literal rows here when this is fixed.

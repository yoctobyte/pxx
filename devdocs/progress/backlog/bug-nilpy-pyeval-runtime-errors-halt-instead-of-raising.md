---
prio: 50
track: N
type: bug
blocked-by: []
---

# pyeval's runtime errors `writeln` + `Halt` instead of raising

- **Type:** bug (NilPy; valid CPython refused) — **Track N**
- **Found:** 2026-08-09, while fixing
  [[bug-nilpy-none-returned-beside-a-container-is-an-unusable-nil-handle]].

```python
x = None
try:
    print(x[0])
except TypeError:
    print("caught")        # CPython: caught
```

pxx prints `pyeval: cannot subscript a non-container` and exits 1. The handler
cannot run, because there is no exception — the runtime called `Halt`.

```
compiler/builtin/pyeval.pas:1062
  begin writeln('pyeval: cannot subscript a non-container'); Halt(1); end;
```

`PySubscriptGet` alone has four such sites (non-container, string index out of
range, list index out of range, bytes index out of range); `grep -n "Halt(1)"
compiler/builtin/pyeval.pas` is the real list.

## Why it matters

It is the same shape as
`bug-nilpy-dunder-protocols-ignored-fall-back-to-handle-arithmetic`, whose fix
note states the rule already: a runtime fault must be a **catchable raise**, not
a halt, because a `try: ... except:` around it otherwise cannot run at all. Real
Python code guards subscripts with `except (TypeError, IndexError)`.

## Shape of the fix

Each site becomes `raise TypeError.Create(...)` / `raise IndexError.Create(...)`
with CPython's own wording (`list index out of range`, `'NoneType' object is not
subscriptable`). pylib's `PyTypeError` / `PyIndexError` helpers are the
precedent; check whether pyeval can reach them or needs its own.

Worth sweeping every `Halt(` in `pyeval.pas` and `pylib.pas` in one pass rather
than one site per ticket — they are one concept, and the ones left behind are
the ones that stay uncatchable.

---
prio: 30
track: N
type: bug
blocked-by: []
---

# `e.args` is missing on exceptions

- **Type:** bug / missing surface (NilPy) — **Track N**
- **Found:** 2026-08-09, same exception sweep as
  [[bug-nilpy-multi-arg-exception-constructor-segfaults]]
- **Loud:** `hasattr(e, "args")` is False and reading it raises AttributeError.

```python
try:
    raise ValueError("boom")
except ValueError as e:
    print(e.args)        # CPython ('boom',)   pxx AttributeError
```

`str(e)` is correct; only the `.args` tuple is absent.

## Why it is worth having

`e.args` is how code inspects an exception's payload without parsing its
message — `code = e.args[1]` next to `raise MyErr("no such user", 404)`. It is
also the natural partner of the multi-argument constructor fixed alongside this:
that fix makes `str(e)` render `('no such user', 404)`, so a program can now SEE
the tuple in the message but cannot INDEX it.

## Shape of a fix

`Exception` currently stores a single `msg: AnsiString`. `.args` wants the
arguments kept as a `TPyList` marked `PYSEQ_TUPLE` (the tuple representation
already used everywhere else), with `str(e)` derived from it rather than stored
separately — CPython's own relationship: `str(e)` is `''`, `args[0]`, or
`repr(args)` for zero, one and many.

Deriving both from one store is what keeps them from disagreeing; the fold added
for the multi-arg fix builds the same string today and would then have a real
tuple to render instead.

Note `Exception` is shared with the Pascal RTL side (sysutils' `Exception` is
shadowed by pylib's, and `Message`/`FMessage` are properties over the same
`msg`), so a new field must not disturb that — see the comment on the class.

## Gate
`.npy` diffed against CPython: `.args` for zero, one and several arguments,
indexing it, `len(e.args)`, a built-in exception, a subclass, and `str(e)`
staying correct for all of them.

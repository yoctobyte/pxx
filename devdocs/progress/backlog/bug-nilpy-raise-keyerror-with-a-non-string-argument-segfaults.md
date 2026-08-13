---
track: N
prio: 40
type: bug
blocked-by: []
summary: "`raise KeyError(42)` SEGFAULTS — an integer argument reaches Exception.Create(const m: AnsiString) as a string handle. Identical on pinned. Every builtin exception ctor takes a string, so this is the whole family, and CPython accepts any object."
---

# `raise KeyError(42)` segfaults

```python
try:
    raise KeyError(42)
except KeyError as e:
    print(e.args)
```

Segfaults at the raise. **PRE-EXISTING** — identical under
`stable_linux_amd64/default/pinned`.

- **Found:** 2026-08-13, sweeping `e.args` for
  [[bug-nilpy-exception-args-attribute-missing]] with a non-string key.
- **Silent and fatal**, which is the worst pair: no diagnostic, no exception,
  just a dead process on a program CPython runs.

## Cause, as far as measured

`Exception.Create` takes `const m: AnsiString` and every builtin exception
inherits it. A NilPy `raise Cls(x)` passes the argument straight through, so an
integer arrives where a managed string handle is expected and the first read of
its length word walks off a small integer. That is the same shape as every
other "a scalar reached a string parameter" crash in this frontend.

Note the multi-argument form does NOT crash: `raise MyErr("a", 42)` is folded to
a rendered string at the construction site, and the fold boxes each argument
through `pyvar_repr`. So it is specifically the ONE-argument non-string raise
that has no conversion.

## Shape of a fix

At the raise/construction site, box a non-string single argument the way the
multi-arg fold already does — `pyvar_repr` for the message — and keep the raw
value for `args` (the `argsv` override that landed with the args ticket is
exactly the slot for it). That makes `str(KeyError(42))` be `42` and
`e.args` be `(42,)`, both matching CPython.

Alternatively refuse it at compile time, which is strictly better than the
segfault but loses an ordinary Python idiom (an integer error code as the
payload).

## Gate

A `.npy` diffed against CPython: `raise KeyError(42)`, a float and a tuple
argument, `str(e)`, `repr(e)` and `e.args` for each, plus the string forms as
controls.

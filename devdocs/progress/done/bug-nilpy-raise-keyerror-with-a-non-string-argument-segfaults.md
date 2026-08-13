---
track: N
prio: 40
type: bug
blocked-by: []
summary: "`raise KeyError(42)` SEGFAULTS — an integer argument reaches Exception.Create(const m: AnsiString) as a string handle. Identical on pinned. Every builtin exception ctor takes a string, so this is the whole family, and CPython accepts any object."
status: done
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

## Log
- 2026-08-13 — resolved, commit PENDING-COMMIT.

## Resolution (2026-08-13)

Fixed as the ticket's first option — box at the construction site — in two
shapes, because the family is not uniform:

- **KeyError** takes a `Variant` message now and reprs it itself. That makes
  `str(KeyError(42))` be `42` (unquoted, CPython's rule for the one builtin
  whose str() is repr(arg)) and `e.args` be `(42,)` with the key's own TYPE.
  `KeyError()` with no argument fills None and renders as `''`.
- **every other exception** keeps `Create(const m: AnsiString)`; the frontend
  boxes the single non-string argument and renders it through the new
  `pyexc_msgstr` (= `str()`, ONE signature so FindProc cannot pick a wrong
  overload — that is how the multi-arg fold crashed while fixing a crash).

Both fire only at `nArgs = 1`, so they cannot overlap with the multi-argument
fold above them, which is untouched.

**Residual, measured, deliberately shipped:** `e.args` for a NON-KeyError
exception is `('42',)` where CPython says `(42,)` — that family's message
parameter is still a string, and widening the RTL's base `Exception.Create` to
a Variant would change every `raise EFoo.Create('..')` in the RTL under a
quick-only gate. Filed as
[[bug-nilpy-non-keyerror-exception-args-loses-the-argument-type]].
`str()` and `repr()` are exact for every shape tested (int, float, bool, tuple,
string, empty, user subclass, multi-arg, and a dict miss).

Verified against CPython by `test/test_nilpy_exception_non_string_argument`
(wired into `test-nilpy`) plus the six existing exception tests re-run by name.

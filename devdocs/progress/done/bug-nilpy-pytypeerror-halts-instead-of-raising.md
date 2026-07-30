---
track: N
prio: 40
type: bug
---

# `PyTypeError` halts the process, so `except TypeError:` cannot catch it

```python
try:
    print(2.5 * "ab")
except TypeError:
    print("caught")       # CPython: caught     pxx: never runs
```

pxx prints `TypeError: expected an integer to repeat a str by, got float` and
`Halt(219)` — the handler is not consulted, and nothing after the try block
runs.

`pylib.pas`:

```pascal
procedure PyTypeError(t: Int64; const want: AnsiString);
begin
  writeln('TypeError: expected ', want, ', got ', PyVarTypeName(t));
  Halt(219);
end;
```

This is the same shape [[bug-nilpy-int-parse-halts-instead-of-raising]] was
opened for and fixed: `pystr_to_int` now `raise ValueError.Create(...)`, and a
NilPy `except ValueError:` catches it. PyTypeError is the member of that family
nobody converted, so every diagnostic routed through it is fatal — including
the several a program could reasonably handle.

Found while gating [[bug-nilpy-float-times-string-hangs]]: the natural
regression test for that fix is a `try/except TypeError`, and it could not be
written.

## Shape of a fix

Raise a `TypeError` exception class the way `pystr_to_int` raises ValueError,
and check every PyTypeError call site for one that runs where an exception
cannot be raised (a callback frame, an ARC finalizer). The message text should
stay recognisable — tests match on it.

## Gate

`make test-nilpy` plus a `.npy` catching TypeError from a float repeat count, a
string in a numeric context, and an uncaught one still terminating with the same
message.

## Log
- 2026-07-30 — resolved, commit 7e90f99e3.

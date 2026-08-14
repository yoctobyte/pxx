---
track: N
prio: 35
type: bug
summary: "`raise ValueError` (the CLASS, no call) compiles and then dies at run time with 'exceptions must derive from BaseException' — the instantiating form `raise ValueError()` works"
---

# `raise ValueError` — the bare CLASS form — fails at run time

- **Type:** bug (NilPy) — **Track N**
- **Found:** 2026-08-15, while building the user iterator protocol
  ([[bug-nilpy-iterator-protocol-on-a-user-class]]); the ticket's own example
  writes `raise StopIteration`, which is how the protocol is usually spelled.
- **Loud, but LATE:** it compiles clean and dies at run time.

```python
try:
    raise ValueError
except ValueError:
    print("caught bare ValueError")
```

```
CPython: caught bare ValueError
pxx:     Unhandled exception: TypeError: exceptions must derive from BaseException
```

`raise ValueError()` — the same statement with the call — works. So does
`raise ValueError("msg")`. Only the bare-class form fails.

Confirmed **pre-existing** at pin v308 and at the stable pinned binary, so it
is not a regression from the iterator work.

## What CPython does

`raise C` where `C` is an exception CLASS is exactly `raise C()` — CPython
instantiates it with no arguments. The message pxx produces is CPython's own
wording for `raise 42`, i.e. for raising a NON-exception; we are producing it
for a case CPython accepts, which means the raise lowering is testing the
raised value for "is an exception INSTANCE" where it should first ask "is this
an exception CLASS, and if so instantiate it".

## Why it matters more than it looks

`raise StopIteration` is the canonical spelling in an `__next__` body — it is
what the iterator-protocol ticket's example writes and what most Python code
writes, because the exception carries no message. The same goes for
`raise NotImplementedError` in an abstract method. So the bare form is not a
rare corner.

## Shape of a fix

In the raise lowering: when the operand resolves to a CLASS rather than an
instance, emit the no-argument construction and raise that. The
"must derive from BaseException" check then applies to the constructed
instance, as it does today for the call form.

## Gate

`.npy` diffed against CPython: `raise ValueError`, `raise StopIteration`,
`raise NotImplementedError`, each caught by its own `except`; a bare
`except Exception:` catching one of them; and a control that
`raise ValueError("msg")` and `raise 42` are unchanged (the second must still
be the TypeError this ticket is about being produced *wrongly*).

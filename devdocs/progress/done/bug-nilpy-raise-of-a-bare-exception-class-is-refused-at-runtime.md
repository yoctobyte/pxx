---
track: N
prio: 35
type: bug
summary: "`raise ValueError` (the CLASS, no call) compiles and then dies at run time with 'exceptions must derive from BaseException' — the instantiating form `raise ValueError()` works"
status: done
owner: agent-AN
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

## Resolution (2026-08-15)

`raise C` now instantiates, as CPython does — through the ORDINARY constructor
path, not a second zero-argument construction written beside it. `PyClassCreate`
learned one flag (`PyCtorNoParens`) that makes it skip the `(` … `)` and the
argument loop; everything else it does — parameter defaults, the inherited-ctor
under-call fill, the dataclass arms, the Exception folds — applies unchanged.
That reuse is what makes `raise MyErr` on `class MyErr(Exception): pass` give
`str(e) == ''` for free, which is the CPython answer.

Two guards decide when the bare form fires, and both matter:

- **a variable wins.** `raise e` on a local holding an instance must not be
  re-constructed, so `FindSym` is asked first.
- **the class must derive from Exception.** `raise SomeOrdinaryClass` is
  CPython's TypeError; constructing it to find that out would run its ctor's
  side effects first, so it stays on the old path where `pyraise_check` answers.

**A second, pre-existing crash was found and fixed in the same statement.**
`raise 42` SEGFAULTED (confirmed on the pinned binary, so not a regression):
the `pyraise_check` guard was reached only from the tyVariant arm, and an int
literal is tyInteger, so the raw value went to IR_RAISE where an instance
pointer belongs. The condition is now "not a class" rather than "is a variant",
with the operand boxed first — one path answering for every non-instance shape,
which is the normalise-don't-special-case call. `raise 42`, `raise "x"` and
`raise 3.5` all give CPython's TypeError now instead of dying.

`test/test_nilpy_iterator_protocol.npy` was switched back to the natural
`raise StopIteration` spelling its subject actually uses; its output is
unchanged, and CPython's is too.

**Gate:** `test/test_nilpy_raise_bare_class.npy` (+`.expected`, wired into the
Makefile) — bare `ValueError`/`StopIteration`/`NotImplementedError`/`KeyError`,
a bare user subclass, `raise C from e`, and controls for `raise C("msg")`,
`raise <variable>` and `raise 42`. All byte-identical to CPython.
`tools/gate.sh quick` GREEN, self-host byte-identical.

The FPC seed caught `PyEnsureExceptionClass` used ~12000 lines above its
definition — the fourth instance of that shape this session; forward added.

## Log
- 2026-08-15 — resolved, commit 213c385ea.

---
prio: 30
track: N
type: bug
blocked-by: []
status: done
owner: claude-A-N
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

## DONE 2026-08-13 — derived, not stored, and with no frontend change at all

`e.args` answers: `('boom',)` for a one-argument raise, `()` for none,
`e.args[0]` indexes, and a program can branch on the payload instead of parsing
the message.

### Why derived

This ticket proposed storing the arguments as a `TPyList` marked
`PYSEQ_TUPLE` and deriving `str(e)` from it. The cheaper direction turned out
to be the same relationship read the other way: a pxx Exception carries one
Message, and for every raise this dialect emits that message IS the single
argument — so `args` is `()` for an empty message and `(msg,)` otherwise, which
is CPython's own args/str relationship for the one-argument case.

It is a Pascal **property** on `Exception`, so there was no frontend work:
NilPy's member path already resolves properties, and `e.args` resolved the day
the property existed.

### KeyError is the exception, and that is what `argsv` is for

`PyKeyError` stores its message ALREADY REPR'D — CPython's KeyError is the one
builtin whose `str()` is the repr of its argument — so deriving args from the
message hands back the QUOTED form for a real missing key. The raise site now
stashes the raw key in a stored `argsv` that `GetArgs` prefers, and
`{}["nope"]` gives `('nope',)`.

### That settled `repr(KeyError(...))` too, which was BLOCKED on this

[[bug-nilpy-exception-str-and-repr-diverge-from-cpython]] excluded KeyError from
the exception repr for a stated and correct reason: quoting the stored message
gives `KeyError("'nope'")` and not quoting it gives `KeyError(k)` for a
user-constructed one — both wrong, in opposite cases, depending on who raised.
`args` removes the ambiguity: repr the ARGUMENT, whoever built the exception,
and the two cases agree. Both `repr(KeyError('inner'))` and the real-miss form
now print `KeyError('inner')` / `KeyError('nope')`, matching CPython. The
user/miss pair in the test is what pins that they agree.

### Left open, stated in the test

- A MULTI-argument raise: its arguments are folded to a rendered string at the
  construction site, so `args` is a 1-tuple of that text. Fixing it means the
  fold stashing the real tuple into `argsv` — frontend work, and the fold's
  argument nodes are already consumed into the fold, so it needs clones.
- `str(KeyError("inner"))` is `inner` here and `'inner'` in CPython: `str(e)`
  for a CAUGHT exception reads the `msg` FIELD through a frontend-synthesised
  access and never reaches the renderer this fixed. The RAISE-path form is
  correct because its message is pre-repr'd.

### Filed while here

`raise KeyError(42)` SEGFAULTS, identically on pinned — a non-string single
argument reaching `Create(const m: AnsiString)`.
[[bug-nilpy-raise-keyerror-with-a-non-string-argument-segfaults]], with the
observation that the multi-arg form does not crash because its fold boxes every
argument.

Test `test/test_nilpy_exception_args.{npy,expected}` (`.expected` from CPython),
wired into `test-nilpy`; all fifteen existing exception tests re-run against
their exact assertions. `compiler/builtin/**`, so pinned in the same commit.
Gate: self-host fixedpoint + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-13 — resolved, commit PENDING-COMMIT.

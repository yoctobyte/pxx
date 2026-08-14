---
prio: 30
track: N
type: bug
blocked-by: []
<<<<<<<< HEAD:devdocs/progress/working/bug-nilpy-exception-args-attribute-missing.md
owner: agent-N
status: done
========
status: done
owner: claude-A-N
>>>>>>>> parent of 2277bf349 (revert(N): e.args -- pylib's Exception cannot carry a member sysutils lacks):devdocs/progress/done/bug-nilpy-exception-args-attribute-missing.md
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
- 2026-08-13 — resolved, commit 67910b097.
<<<<<<<< HEAD:devdocs/progress/working/bug-nilpy-exception-args-attribute-missing.md


## REVERTED 2026-08-13, same day it shipped — and why it cannot be re-landed as written

Track T's NATIVE tier turned `test_uses_order_pylib_exception_a` RED against
this work. It is a real breakage, not a flake: the PINNED compiler reproduces
it, and `gate.sh quick` cannot see it (the test runs only in the native tier),
which is why it shipped and pinned green.

`args` was a field (`argsv`) plus a method (`GetArgs`) on pylib's `Exception`.
Under `uses sysutils, pylib` those are unreachable from pylib's own code,
because the name `Exception` deliberately resolves to SYSUTILS' class even
while pylib is being compiled — four spellings tried, four different compile
errors, all inside pylib. Full measurement and the four ways out:
[[decide-pylib-exception-vs-sysutils-exception]], which this ticket is now
blocked on.

**What was kept:** the KeyError constructor still takes a Variant, so
`str(KeyError(42))` is `42` and `repr` is `KeyError(42)` — both CPython-exact,
and correct now on BOTH construction paths, which is what the args-based
renderer arm had been written to achieve. That part needed no new member.

**What was removed:** `argsv`, `GetArgs`, `property args`, the two renderer arms
that read them, and `test/test_nilpy_exception_args` with its Makefile row.

**For whoever picks this up:** do not re-add a member to pylib's `Exception`.
Read the decide ticket first; option 3 there (a pointer-keyed side table reached
through plain functions) is the shape that satisfies the constraint if the two
classes must stay separate.

## 2026-08-14 — UNBLOCKED: the constraint is gone

pylib's Python root is `PyException` now
([[decide-pylib-exception-vs-sysutils-exception]] option 5, commit 6ed45773f).
It is pylib's own class, declared under a name no other unit uses, so **"do not
add a member to pylib's Exception" no longer applies** — the whole reason it
applied was that `Exception` resolved to SYSUTILS' class while pylib itself was
being compiled, and there is no shared name left to resolve.

So re-land the ORIGINAL shape, not option 3's side table: `argsv` field,
`GetArgs`, `property args`, the two renderer arms, and
`test/test_nilpy_exception_args` with its Makefile row. The advice at the end of
the section above is superseded.

**Keep the gate honest:** `test_uses_order_pylib_exception_a`/`_b` are what
caught this the first time and they run only in the NATIVE tier, so
`gate.sh quick` still cannot see a regression here. Both must be green, and they
now assert IDENTICAL output for the two uses orders.
========
>>>>>>>> parent of 2277bf349 (revert(N): e.args -- pylib's Exception cannot carry a member sysutils lacks):devdocs/progress/done/bug-nilpy-exception-args-attribute-missing.md

## RE-LANDED 2026-08-14 — the original member-based shape, unchanged

`git revert` of the revert (2277bf349), conflicts resolved onto the
`PyException` rename. Nothing about the FEATURE was redesigned: `argsv` is a
stored field again, `GetArgs` a method, `args` a property — exactly what "do not
re-add a member to pylib's Exception" forbade, and exactly what is fine now that
the class is pylib's own and shares its name with nothing.

Option 3 (a pointer-keyed side table reached through plain functions) was NOT
built and should not be: it existed only to route around a constraint that no
longer exists.

### The canary that killed it last time, in both uses orders

`test_uses_order_pylib_exception_a` and `_b` are green — that is the whole
proof, because they are what turned RED in Track T's native tier the night this
shipped, and `gate.sh quick` still cannot see them. Both print identical output
now (see [[bug-pascal-uses-order-breaks-pylib-exception]]).

Also green: `test_nilpy_exception_args` and
`test_nilpy_exception_non_string_argument` against their recorded CPython
expectations, plus `test_nilpy_rtl_exception_surface` and
`test_nilpy_pyexception_bare_vs_qualified`.

### Still open, unchanged from the original write-up

- a MULTI-argument raise folds its arguments to a rendered string at the
  construction site, so `args` is a 1-tuple of that text until the fold stashes
  the real tuple (needs argument-node clones — frontend work);
- `str(KeyError("inner"))` is `inner` here and `'inner'` in CPython, because
  `str(e)` for a CAUGHT exception reads the `msg` FIELD through a
  frontend-synthesised access and never reaches the renderer.

Neither is a regression and neither is what this ticket was about.
- 2026-08-14 — resolved, commit 52c37f07a.

## 2026-08-14, measured after the ctor widening — one of the two residuals is GONE

Re-ran both residuals at HEAD instead of carrying the old text forward:

- `str(KeyError("inner"))` is **`'inner'`**, matching CPython. It was `inner`
  when the residual was written; widening the base ctor to a Variant fixed it as
  a side effect, because the message KeyError stores is now the repr on every
  construction path and `str(e)` reads that field. **Do not go hunting for it.**
- The multi-argument raise is still real and is now its own ticket:
  [[bug-nilpy-multi-arg-exception-args-is-a-1-tuple-of-rendered-text]].
  `MyErr('a', 404).args` is a 1-tuple of the rendered text, so `len(e.args)` is
  1 and `e.args[1]` is wrong. `str(e)` agrees with CPython.

That is the whole remaining gap in this family.

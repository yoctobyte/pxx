---
track: N
prio: 60
type: bug
status: done
owner: claude-an-1
---

# `obj(...)` does not dispatch a user `__call__`

```python
class C:
    def __call__(self, x):
        return x * 2
c = C()
print(c(5))
```

CPython prints `10`. pxx returns a garbage integer (pinned does the same).

Found while fixing `bug-nilpy-calling-a-non-callable-segfaults`, and left out
of that fix deliberately: the guard there refuses a tag-7 instance **only when
its class has no `__call__`**, so a list/dict/tuple now raises TypeError
properly while an instance that defines `__call__` still falls through to the
old path rather than being newly refused. Refusing it would have turned a wrong
value into a wrong error — a regression — so the arm stays narrow and the
dispatch is this ticket.

## Where it goes

`pyvar_callv0..3` in `pyeval.pas` already resolve the class of a tag-7 payload
(`GetInstanceRTTI`), and `PyHostCall(vmobj, name, args, res)` is the existing
machinery for calling a method by name with a `TPyList` of arguments —
`PyFindMethCI(cls, '__call__')` plus `PyHostCall` should be most of it.

Note `pylib.pas` already has `PyNotCallableError` ("object is not callable (no
`__call__`)") written and **never called** — it was authored for this arm and
left unwired.

## Gate

`make test-nilpy` + self-host byte-identical, CPython-diffed over `__call__`
with 0/1/2/3 args, an inherited `__call__`, and a class WITHOUT one still
raising TypeError.

---

## Correction to this ticket: the repro in the body was never broken

Measured on `pinned` before touching anything — the ticket's own program:

```python
class C:
    def __call__(self, x):
        return x * 2
c = C()
print(c(5))          # pinned prints 10. Correct, and always has been.
```

So "pxx returns a garbage integer (pinned does the same)" is **wrong**. That
spelling takes the STATIC path: the frontend knows `c`'s class and lowers a
direct method call, never reaching a dispatcher at all.

The defect is the **dynamic receiver** — every route that loses the static type:

```python
d = {"c": c};  d["c"](5)      # pinned: SEGFAULT
lst = [c];     lst[0](5)      # pinned: SEGFAULT
def get(): return C()
get()(5)                      # pinned: SEGFAULT
def apply(f, v): return f(v)
apply(c, 5)                   # pinned: SEGFAULT
```

There the receiver is a VARIANT, `pyvar_callv<n>` runs, `PyNotCallable` passes
it (it refuses a tag-7 instance only when the class has NO `__call__`), and the
INSTANCE POINTER is then called as a code address. A crash, not a wrong value.

Worth recording because the wrong description is what made this look like a
value bug for the whole time it was open, and because it is the second ticket in
this family whose stated repro did not reproduce (see the
`(3 + 4)(x)`-is-a-parser-bug note in
`feature-nilpy-a-callable-value-needs-its-own-variant-tag`).

## Resolution

`PyCallDunder` in pyeval.pas — receiver + argument list into the existing
`PyHostCall` by-name trampoline, offered from all four of `pyvar_callv0..3`
right after `PyNotCallable` and answering False for anything that is not a
tag-7 instance with a `__call__`, so every other callee falls through unchanged.
`PyFindMethCI` walks the parent chain, so an inherited `__call__` works and the
confirmed-method precondition is what makes `PyHostCall`'s missing-method
`Halt` unreachable from here.

`pylib`'s `PyNotCallableError` is left unwired: `PyNotCallable` already raises a
catchable TypeError for a `__call__`-less instance, and routing through a second
raiser would change the message a test matches on for no behavioural gain. Its
zero-caller state is now deliberate rather than an oversight.

### Verification

`test_nilpy_dunder_call.npy` (the test that already existed and was gated by an
inline Makefile expectation) extended with the dynamic routes: dict, list, call
result, unannotated parameter at arities 0/1/3, an inherited `__call__` both
directly and through a dict, and a class WITHOUT one reached the same dynamic
way still raising catchably. Output is byte-identical to CPython's.

## Log
- 2026-08-11 — resolved, commit ea9ed57c5.

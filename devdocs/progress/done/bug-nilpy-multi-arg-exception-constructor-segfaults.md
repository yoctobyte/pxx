---
prio: 55
track: N
type: bug
blocked-by: []
---

# A multi-argument exception constructor SEGFAULTED

- **Type:** bug (NilPy, **crash**) — **Track N**
- **Found:** 2026-08-09 by a differential sweep of exception semantics.
- **Status:** done

```python
class MyErr(Exception):
    pass

raise MyErr("boom", 42)     # CPython: MyErr: ('boom', 42)   pxx: SIGSEGV
e = MyErr("a", 1)           # not even raised — still SIGSEGV
```

Zero and one argument were fine. Two or more crashed.

## Cause

Python's `Exception` takes `*args` and `str(e)` renders the tuple. The RTL's
`Exception.Create(msg)` takes exactly one, and `PyClassCreate` emitted the
surplus arguments anyway, so the callee read them as parameters it does not
have.

The mirror case — an UNDER-call, `MyErr()` where `Create` wants a message — was
already handled a few lines above, with its own ticket
(`bug-nilpy-raise-of-empty-exception-subclass-with-no-args`). The over-call was
the other half of the same asymmetry and was never covered.

## Fix

For an `Exception`-derived class whose inherited ctor takes one string, two or
more arguments are folded into the single message CPython would print:
`'(' + repr(a) + ', ' + repr(b) + ')'`. One argument is left completely alone —
`str(MyErr("boom"))` is `boom`, not `('boom',)`.

### The fix's own bug, worth recording

The first version used `pyrepr_of`, which is **overloaded per argument type**,
and `FindProc` resolves by name and never consults overloads
([[project_findproc_by_name_ignores_overloads]]). It bound the AnsiString
overload, so `MyErr("boom", 42)` passed the integer `42` to a routine expecting
a string handle — and crashed in a NEW place. The fix reproduced the symptom it
was fixing, and a test using only string literals would have passed.

Now each argument is boxed with `PyForceVariant` and rendered by `pyvar_repr`,
which has ONE signature and decides the type at run time.

## Gate
`test/test_nilpy_exception_multi_arg.{npy,expected}` (`.expected` from CPython):
zero/one/two/three arguments, a subclass two deep, a built-in exception
(`ValueError("v", 9)`), and non-string arguments — int, float, list and a
VARIABLE — which is the class of case that catches the overload trap above.

## Left open
`e.args` is still missing (`hasattr(e, "args")` is False, and reading it raises
AttributeError). Loud, and a separate piece of surface:
[[bug-nilpy-exception-args-attribute-missing]].

## Log
- 2026-08-09 — resolved, commit PENDING-COMMIT.

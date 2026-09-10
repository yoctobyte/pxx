---
slug: bug-n-a-local-holding-a-callable-is-shadowed-by-a-pascal-intrinsic-at-the-call
track: N
type: bug
prio: 70
status: backlog
owner: ""
created: 2026-09-10
found-by: frankB
tags: [nilpy, values, shadowing, silent-wrong-value]
blocked-by: []
summary: "`lo = f` then `lo(2)` prints `2` and `hi = f` then `hi(2)` prints `0`, where CPython prints f's result. A NilPy LOCAL holding a callable, spelled like a Pascal intrinsic, is answered by the INTRINSIC at the call — no diagnostic, no crash, a plausible wrong number. `abs = f` is the same. `ord = f` is CORRECT, which is the control that makes this a shadowing bug rather than a builtin-name policy: `ord` is a Python builtin too and it binds the local. The assignment is fine — the value is built correctly — so this is the CALL door reading the name, and `f(2)` on the same def is right throughout. Found while testing the module-member-as-a-value group; it made an unrelated test row red for a reason nothing in that row could explain."
---

# Measured 2026-09-10, compiler `de51b67ba86b`

```python
def f(x):
    return "f " + str(x)

lo = f
print(lo(2))     # pxx: 2        CPython: f 2
hi = f
print(hi(2))     # pxx: 0        CPython: f 2
ord = f
print(ord(2))    # pxx: f 2      CPython: f 2
abs = f
print(abs(2))    # pxx: 2        CPython: f 2
```

Four rows, three wrong, no diagnostic on any of them. `Lo(2)` is 2, `Hi(2)` is 0
and `Abs(2)` is 2 — every wrong answer is the Pascal intrinsic's answer for the
argument, which is why they look like plausible values rather than corruption.

## The boundary, and why `ord` is the row that matters

`ord` is as much a Python builtin as `abs` is, and it binds the local correctly.
So this is **not** a policy about builtin names being reserved: it is the set of
names the PASCAL side treats as intrinsics leaking into a NilPy local's call
site. Any probe that used `abs` alone would have been read as "NilPy reserves
Python builtins", which is a different and wrong diagnosis.

The ASSIGNMENT is correct: the callable value is built (a `pybound_new` pair),
and `print(lo)` renders a function object. It is the CALL that re-reads the
NAME and reaches the intrinsic instead of the symbol in scope.

## Why it is worth prio 70

`lo` and `hi` are ordinary variable names in any code that deals with ranges,
bounds or bisection, and `abs` is one of the most common shadowings in real
Python. The failure is silent and returns a number of the right type, so it
surfaces as a wrong result far from the assignment — the expensive class this
repo's own debugging notes are about.

Not blocking a lekkerzeilen module today. Found because it made
`test_nilpy_a_module_member_value_is_case_sensitive.npy` red on a row whose
subject was module case-folding, and nothing in that row could have explained
it; the variable in that test is now named `lower_fn` and says why.

## Where to start

The value side is fine, so this is the call door: the site that decides a
`name(args)` where `name` is a local holding a Variant. Compare with `ord`,
which takes the correct path today — the two must be reaching different
resolution orders, and the one `ord` takes is the right one.

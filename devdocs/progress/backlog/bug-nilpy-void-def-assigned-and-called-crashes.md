---
track: N
prio: 55
type: bug
---

# NilPy: a `-> None` def assigned to a name, then called, segfaults

Found by accident while researching
[[bug-nilpy-callable-value-abi-sorted-key-and-builtins]] (nothing to do with
that ticket's fix — confirmed present against `stable_linux_amd64/default/pinned`
from BEFORE any of that session's changes).

## Repro

```python
def hit(vm) -> None:
    print("native ran")

f = hit
f(1)
print("done")
```

```
native ran
Segmentation fault (core dumped)
```

CPython prints `native ran` then `done`. pxx crashes right after `hit`'s own
body finishes running — `print("done")` never runs.

## What's odd

The SAME def, captured the SAME way, does NOT crash when stored in an object
field and called through it instead (`w.native = hit` then `w.native(x)` —
see `test_nilpy_unpack_callable.npy`, gated and green). Only the plain
`f = hit; f(1)` shape (assignment to a bare name, then a direct call on that
name) crashes.

## Where it likely is

`PyMakeFuncValue` (pyparser.inc) boxes `hit` via `pybound_new(procAddr, nil)`
(the same Shape-A bound-method-with-nil-receiver representation described in
[[bug-nilpy-callable-value-abi-sorted-key-and-builtins]]'s research). `hit`
has `Procs[hit].IsFunc = False` (a `-> None` def with no value-returning
`return` registers as a Pascal PROCEDURE, not a function — confirmed via a
temporary debug print during that ticket's investigation). The Shape-A call
bridge (`pycallback_call1`/`pyvar_callv1`) unconditionally casts the callee
through a Variant-RETURNING type (`TPyCbF1`/`TPyCallFn1`) regardless of
whether the real proc is a function or a procedure — a genuine PROCEDURE
has no Variant hidden-destination-pointer convention at all, so the call
bridge's implicit expectation that the callee filled one in is never met.
This is plausible but NOT confirmed with a debugger/IR dump; measure before
fixing (this project's own debugging-playbook: reach for `PXXDBG=a.ir` /
`-g` + gdb, don't reason from a plausible story).

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` matching the
repro above (a `-> None` def assigned to a bare name, called, followed by a
statement that must still run), diffed against CPython.

---
track: N
prio: 25
type: bug
summary: "`obj[k] = v` on a class with no __setitem__ raises 'object does not support item assignment (no __setitem__)' where CPython names the class — the sibling read error already names it"
---

# `PyNoSetitemError` does not name the class

```python
class ReadOnly:
    def __getitem__(self, k): return k
ReadOnly()["x"] = 2
```

| | message |
| --- | --- |
| CPython | `'ReadOnly' object does not support item assignment` |
| pxx | `object does not support item assignment (no __setitem__)` |

Correct BEHAVIOUR — a `TypeError`, at run time, catchable — and the wrong
wording. Small, but worth fixing because its own sibling already does it right:
the READ refusal raises `'SetOnly' object is not subscriptable`, naming the
class exactly as CPython does (`PyNotSubscriptableNode` passes the name in). So
the two halves of one feature disagree, and the half that reads worse is the one
a user hits while debugging a write.

Also note the parenthetical `(no __setitem__)` is implementation-facing — it
names the dunder rather than the class, which is backwards for a user-facing
diagnostic.

## Fix

`PyNoSetitemError` (pylib) takes no arguments. Give it the class name the way
`PyNotSubscriptableNode` does, and pass it from the three call sites in
`parser.inc`'s subscript arm.

## Gate

CORRECTED 2026-08-09: this needs **no re-pin**. `compiler/compiler.pas` does not
link `pylib` (it uses SysUtils, Math, BaseUnix, asmcore), so a pylib change
cannot move the compiler binary and the self-host fixedpoint still converges
FROM PINNED — measured on
[[bug-nilpy-a-variant-argument-binds-a-class-overload-and-is-unwrapped-unchecked]].
The A != B effect is specific to the builtin units the COMPILER itself links
(builtinheap and friends), not to `compiler/builtin/**` as a directory. So this
is ordinary per-fix-loop work. `test_nilpy_not_subscriptable.npy` already exercises both write cells;
it asserts only the LABEL there, and would assert the full message once this
lands.

## Found by

[[bug-nilpy-setitem-without-getitem-write-does-not-compile]], whose 2x2 test
made the asymmetry visible — the read cells could be diffed against CPython
verbatim and the write cells could not.

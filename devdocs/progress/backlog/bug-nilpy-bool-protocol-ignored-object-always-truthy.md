---
summary: "NilPy: __bool__ and __len__ are ignored in a truth test — every non-nil object is truthy, so `if obj:` takes the WRONG BRANCH silently"
type: bug
track: N
prio: 65
---

# `__bool__`/`__len__` ignored — every object is truthy, silently

- **Type:** bug (NilPy semantics, silent wrong branch) — **Track N**
- **Opened:** 2026-08-01, found by an operator×operand differential sweep against
  CPython (1094 cases).

## Measured (self-hosted binary at `3f2c5b915`)

```python
class C:
    def __bool__(self):
        return False
c = C()
if c:
    print("truthy")
else:
    print("falsy")
print(not c)
```
CPython: `falsy` / `True`. pxx: **`truthy` / `False`.**

And via `__len__`, which CPython falls back to when `__bool__` is absent:

```python
class C:
    def __len__(self):
        return 0
if C(): print("truthy")
else:   print("falsy")
```
CPython: `falsy`. pxx: **`truthy`.**

## Why this is the dangerous class of bug

It does not raise and does not print a garbage number — it silently takes the
**other branch**. An empty custom collection tests as non-empty, a `__bool__`
that means "invalid/unset" tests as valid. Nothing in the output looks wrong.

## Cause — an incomplete fix, not a missing one

This is the unfinished tail of the `not <x>` family recorded in
`project_nilpy_truthiness_keyed_on_handle_family`. `not x` originally
complemented the HANDLE (never nil ⇒ always True) and was fixed three times:

- string → `Length(s) = 0` (`bug-nilpy-not-on-string-always-true`)
- pylib container → `.count = 0` (`bug-nilpy-not-on-container-always-true`)
- **any other object, incl. user classes → `o = nil`**
  (`bug-nilpy-not-on-object-always-true`, 638e4a82e)

That third fix is the one that is wrong in general: `o = nil` is only CPython's
answer for a class defining *neither* dunder. CPython's actual rule is
`__bool__` first, then `__len__() != 0`, then "always true". pxx implements only
the last step.

Consistent with the audit finding that **`__bool__` appears nowhere in
`compiler/**`** (`grep -oh '__[a-z_]*__' compiler/*.inc`), so nothing can be
dispatching it.

## Scope

Every truth context, not just `not`: `if obj:`, `while obj:`, `and`/`or`
operands (note `decide-nilpy-and-or-return-operand-or-bool` — `and`/`or` return
the OPERAND, so the truth test is separate from the result), `bool(obj)`, and a
conditional expression. Fixing only `not` would repeat the three-times-for-one-bug
history above.

## Fix shape

One truthiness helper used by all contexts: dispatch `__bool__` if declared,
else `__len__() != 0` if declared, else the current `o = nil`. The existing
string/container arms stay as they are — they are the same rule specialised for
types whose dunders are known statically.

`__len__` already dispatches (`bug-nilpy-dunder-protocols-ignored-...`), so the
second arm is wiring, not machinery.

## Gate

`make test-nilpy` + self-host byte-identical, and a `.npy` diffed against
CPython covering: `__bool__` False/True, `__len__` 0/non-zero, both declared
(`__bool__` wins), neither declared (non-nil ⇒ truthy), and each truth context
above. Related: [[bug-nilpy-dunders-not-dispatched-through-containers]].

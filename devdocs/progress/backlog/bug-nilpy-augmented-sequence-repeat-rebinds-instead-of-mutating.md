---
track: N
prio: 20
type: bug
blocked-by: []
summary: "`xs *= 2` on a list REBINDS where CPython mutates in place, so an alias taken beforehand keeps the old contents. Only observable through an alias; the value bound to the name itself is correct."
---

# `*=` on a list rebinds instead of mutating

```python
a = [1, 2]
alias = a
a *= 2
print(a)        # [1, 2, 1, 2]   agrees
print(alias)    # CPython [1, 2, 1, 2]   pxx [1, 2]
```

Filed 2026-08-15 alongside
[[bug-nilpy-augmented-multiply-on-a-sequence-yields-empty]], which made `a *= 2`
produce a value at all (it was silently EMPTY). The rebind is what that fix
does; the in-place half is this ticket.

Silent, and narrow: it needs an alias taken before the statement. `+=` is
already correct here — it calls `TPyList.extend`, which mutates — so the two
augmented sequence operators disagree, and that asymmetry is the thing to
remove.

## Shape of a fix

`*=` wants the in-place primitive `+=` has: a `TPyList.repeat_inplace(n)` (append
the existing elements n-1 times, in place, then answer Self), called from
`PyAugMulNode`'s list arm the way the `+=` site calls `extend`. Then the three
augmented sites need no further change.

A str `s *= 2` is NOT part of this: Python strings are immutable, so rebinding
IS the semantics there. Bytes: `bytearray` mutates and `bytes` does not — check
which one `PyBytesRepeatPair` covers before touching it.

## Gate

`.npy` diffed against CPython: the alias above; an alias inside a list; a list
held in a dict value; `*= 0` and `*= 1` through an alias; a str alias (which
must keep REBINDING); and the non-alias rows from
`test_nilpy_augmented_sequence_repeat.npy` unchanged.

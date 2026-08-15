---
track: N
prio: 20
type: bug
blocked-by: []
summary: "`xs *= 2` on a list REBINDS where CPython mutates in place, so an alias taken beforehand keeps the old contents. Only observable through an alias; the value bound to the name itself is correct."
status: done
owner: claude-AN
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

## Resolution (2026-08-15)

`pylist_repeat_inplace(l, n)` — `+=`'s missing twin, exactly as the sketch
said. It snapshots the original elements first (appending to the list being
read would feed on its own output), and `n <= 0` clears, which is CPython's
answer for `xs *= 0`.

Two things the sketch did not have, both found by measurement:

**A TUPLE must NOT mutate.** The same class carries both, so the question is
asked once inside the helper (`FKind <> PYSEQ_LIST` falls back to the
fresh-list `pylist_repeat`) rather than at a call site that cannot know the
run-time kind. Without it `t *= 2` made an alias of a tuple see a change Python
guarantees it cannot.

**The in-place form must NOT be wrapped in a store.** Both augmented sites
built `target := <repeat>` around it, and through a FIELD target that released
the list before the append ran: `h.xs *= 2` came out EMPTY while the identical
local was right. `PyAugMulInPlace` says the mutation IS the statement, and both
sites read it. (Plain self-assignment `h.xs = h.xs` is fine — measured — so
this is specific to the store being sequenced around a mutation of its own
operand.)

## What is left

A target that reads as a VARIANT — an unannotated parameter, a dict value, a
list element — still rebinds, because the in-place arm keys on the static type.
Filed as [[bug-nilpy-augmented-repeat-on-a-variant-target-still-rebinds]], with
the note that `+=` has the identical split and the identical missing half.

## Gate

`make compiler/pascal26` + `tools/gate.sh quick` GREEN; pinned v337.
`test/test_nilpy_augmented_repeat_mutates_in_place.npy`, byte-identical to
CPython: the alias, an alias inside a list, one in a dict value, `*= 0` and
`*= 1`, a str (which must keep REBINDING), a tuple (likewise), `+=` for
comparison, and field and subscript targets. `test_nilpy_augmented_sequence_repeat`
unchanged.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.

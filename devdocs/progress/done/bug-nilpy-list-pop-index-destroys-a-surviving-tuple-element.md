---
track: N
prio: 45
type: bug
summary: "In uforth, `lst.pop(idx)` on a list of tuples leaves the SURVIVING element as an empty tuple `()` — the popped item is returned intact, its neighbour is destroyed. Kills the ANS tools word set (CS-ROLL) with a 12-line Forth repro; the equivalent standalone NilPy shapes all pass, so the trigger is still unisolated."
status: done
owner: claude-A-uforth
---

# `pop(index)` destroys the element that shifts down — in uforth, not yet in isolation

uforth's `CS-ROLL` is a three-liner over the control-flow stack:

```python
idx = len(vm.control_flow_stack) - 1 - u
item = vm.control_flow_stack.pop(idx)
vm.control_flow_stack.append(item)
```

Probed on both runtimes with the same input (a `print` on each side of the pop):

```
CPython:  before [('dest', 1), ('orig', 2)]   item ('dest', 1)   after [('orig', 2), ('dest', 1)]
pxx:      before [('dest', 1), ('orig', 2)]   item ('dest', 1)   after [(), ('dest', 1)]
```

The popped item is correct. The **neighbour that shifts down** — `('orig', 2)`,
which `pop` only moves — comes back as an EMPTY tuple. Everything downstream
reads a control-flow entry with no fields and the compile of the next definition
dies (SEGFAULT, or `list index out of range` then a hang, depending on how far
it gets).

## Forth repro (12 lines, in the uforth tree)

```forth
: ?DONE POSTPONE IF 1 CS-ROLL ; IMMEDIATE
: PT6
   >R
   BEGIN
      R@
   ?DONE
      R@
      R> 1- >R
   REPEAT
   R> DROP
;
5 PT6 . . . . . CR
```

CPython prints `1 2 3 4 5`; pxx dumps core. The crash is at COMPILE time of
`PT6` (defining `?DONE` alone is fine), which is where `?DONE` runs its
`POSTPONE IF 1 CS-ROLL`.

## What is NOT the cause — measured

Every standalone shape tried matches CPython exactly, so the obvious suspects
are cleared:

- `L.pop(1)` / `L.pop(0)` / `L.pop()` on a list of ints;
- `pop(0)` on a list of tuples, lists, strings, or dicts, at module scope;
- the same pop-and-append against a list held in an OBJECT FIELD, from inside a
  function taking the object as a parameter — i.e. `roll(vm, u)` in isolation
  round-trips `[('dest', 1), ('orig', 2)]` correctly.

So the trigger needs something about how uforth's entries got onto that list, or
about `w_cs_roll` being a captured nested def registered as a native word,
rather than about `pop(index)` on its own. Isolating it is the first job here —
vary how the tuple is BUILT (literal vs from variables vs from a call) and where
the list lives, per the vary-the-shape rule.

Worth checking against
[[bug-nilpy-a-borrowed-object-returned-through-a-call-is-over-released]] before
starting: an element destroyed while a neighbour survives is the same *symptom
family* as an over-release, and that one has a confirmed root cause. If the
tuple was put on the list through a shape that hands out a borrow, this may be
the same bug wearing a different coat.

## Found by

uforth's ANS `toolstest.fth` (line 153), via
[[bug-nilpy-uforth-ans-word-set-suite-4-of-13-open]] — the word set gets 6 of
its 10 TESTING groups in, then hangs (rc 124).

## Gate

`toolstest.fth` byte-identical to CPython running the same uforth.py, plus a
`.npy` regression test for whatever the isolated shape turns out to be.

## Log
- 2026-08-08 — resolved, commit PENDING-COMMIT.

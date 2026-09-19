---
slug: bug-n-a-method-that-calls-a-method-with-a-list-argument-loses-its-own-result
title: a method that calls another method with a list argument loses its own result
summary: >
  NO LONGER REPRODUCES (2026-09-19, frankD). Every row of this ticket's own
  matrix is correct at HEAD and under pin v411 -- returned directly, through a
  local, list bound first, a dict, a nested list, the larger class that used to
  SEGFAULT, and all three controls. A fixture now pins the shape:
  test/test_nilpy_a_method_passes_a_list_to_a_method.npy, 10 rows, wired into
  test-nilpy. THE CAUSE IS UNATTRIBUTED and that is stated rather than guessed.
  It is NOT the by-ref ABI fix, measured twice and independently: b48c40d28
  filed this ticket saying so in its own words ("it fails with the callee
  declared first as well"), and disabling PyMarkVariantParamsByRef reddens
  test_nilpy_a_callee_declared_below_its_caller while leaving every row here
  green. A bisect over the range would settle it and was not spent.
track: N
type: bug
prio: 70
owner: unassigned
status: done
---

## The measurement

2026-09-13, binary 7dd049d55f6d, and identical under pin v408. CPython is the
oracle and answers 3 on every row.

    class L:
        def take(self, r):
            return len(r)
        def go(self):
            return self.take(["a", "b", "c"])

    print("B", L().go())            # CPython: B 3      pxx: "B " -- empty

Four rows, each its own file:

| | pxx |
| --- | --- |
| `return self.take([...])` | **"B "** (empty) |
| `n = self.take([...])` then `return n` | **"B "** (empty) |
| `a = [...]` then `return self.take(a)` | **"B "** (empty) |
| the same two as module-level **functions** | B 3 -- correct |
| `L().take([...])` called from module level | 3 -- correct |
| `self.take_int(3)` -- an INT argument | correct |

So: a method calling a method, with a CONTAINER argument. The argument's spelling
does not matter (literal, local, or a call result); the parameter being a
container does.

**It is not a wrong value, it is corruption.** With a print inserted before the
return, the inner value is right and the program then ENDS:

    inner 3
    (nothing -- the outer print never runs)

and in a class carrying a few more methods the same program SEGFAULTS (rc=139),
on the pin and at HEAD alike. Two different symptoms from one source file across
runs is what says the stack is being damaged rather than a value mistyped.

## What it is NOT

It is not
`bug-n-a-callee-declared-below-its-caller-gets-the-argument-by-the-wrong-abi`
(fixed 2026-09-13, the variant-parameter IsRef timing). This shape fails with the
callee declared FIRST as well, it fails with an explicit `-> int` return
annotation, and it still fails at the tree that carries that fix. It was found
beside it and separated by measurement.

## Where to start

The inner call returns correctly, so suspect the CALLER's result handling: a
method whose result comes straight from another method call, where the callee
took a by-reference variant parameter whose temp the caller allocated. The
argument boxing in `IRLowerCallArg` allocates a hidden variant temp and passes
`IR_LEA` of it; a method frame that then returns the callee's result may be
releasing or reusing that temp's slot across the return.

`PXXDBG=a.ir:L.go` beside `PXXDBG=a.ir:go` for the working module-function twin
is the one-command diff, and the two differ in very little.

## Not established

Whether the same shape breaks for a `dict` or `bytes` argument, or only for a
list; and whether a NON-method caller of a method (a module function calling
`o.take([...])`) is affected.

## Re-measured 2026-09-19 (frankD) -- gone, and the fixture is the point

Taken as one of a three-ticket dispatch group. Re-measured FIRST, because three
pointers had already turned out stale that week, and this one had too.

**Every row of the matrix above is now correct**, at HEAD and under pin v411:
`return self.take([...])`, `n = self.take([...])` then `return n`, the list
bound first, a DICT argument, a nested list, the module-level function controls,
the method reached directly from module level, and the INT-argument control.
Plus the larger class with four instance fields of different kinds, which is the
shape this ticket recorded as SEGFAULTING rather than printing empty.

**WHAT FIXED IT IS NOT KNOWN, AND I TRIED AND FAILED TO ATTRIBUTE IT.** Recorded
because a wrong attribution is worse than an absent one:

- The obvious candidate was `b48c40d28`, which repaired a container argument
  crossing to a method by the wrong ABI. **It is not that**, and the author of
  that commit had already established it -- the same commit message that filed
  THIS ticket separates them by measurement: *"it fails with the callee declared
  first as well"*.
- Confirmed independently rather than taken on trust. `PyMarkVariantParamsByRef`
  was disabled with an `Exit;` and the compiler rebuilt (probe binary
  60833d8250ea): that REDDENS `test_nilpy_a_callee_declared_below_its_caller`,
  so the probe is effective -- and it leaves **every row of the new fixture
  green**. The two defects are genuinely unrelated.
- A bisect over the range since 7dd049d55f6d would settle it. Not spent, under a
  token constraint, and the value of the answer is low now that the shape is
  pinned.

**So the fixture is the deliverable, not the diagnosis.** A defect that was
silent memory corruption, repaired by events with nobody knowing which event,
and with no regression test, is one refactor away from returning unnoticed.
`test_nilpy_a_method_passes_a_list_to_a_method.npy` gives every row a different
length so a diff names the row that moved, and no row's expected value is the 0
or the empty container a broken path also produces.

**Honest limit on that fixture, stated in its own header too: no binary on this
box reddens it.** The defect predates pin v411 and every compiler here carries
whatever fixed it, so there is no negative control, and the one I tried to
manufacture measured a different mechanism. It is a regression guard, not a
proof.

## Log
- 2026-09-19 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 04ce1c7f1.

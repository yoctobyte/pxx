---
slug: bug-n-a-method-that-calls-a-method-with-a-list-argument-loses-its-own-result
title: a method that calls another method with a list argument loses its own result
summary: >
  `return self.take(["a", "b", "c"])` inside a method prints NOTHING for the
  caller's result -- and in a larger class the same shape SEGFAULTS, so it is
  memory corruption rather than a wrong value. The inner call is fine: a probe
  that prints the result before returning it shows the right number and then the
  program simply ends, with the outer print never running. Module-level
  FUNCTIONS in the same shape are correct, and so is the same method called
  directly from module level, so it takes a method calling a method. Identical
  on pin v408 and at HEAD, i.e. pre-existing.
track: N
type: bug
prio: 70
owner: unassigned
status: backlog
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

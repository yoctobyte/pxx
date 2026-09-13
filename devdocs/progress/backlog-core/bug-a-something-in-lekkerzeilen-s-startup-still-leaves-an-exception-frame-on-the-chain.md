---
slug: bug-a-something-in-lekkerzeilen-s-startup-still-leaves-an-exception-frame-on-the-chain
title: something in lekkerzeilen's startup still leaves an exception frame on the chain
summary: >
  A SECOND instance of the class 82e070429 fixed, not yet reduced. After
  `self.keys = bindings.load(...)` returns (app.py:780), the main thread's
  TLS_SLOT_EXC_TOP holds a frame address BELOW the caller's own rsp -- a dead
  frame -- where before the call it held the caller's live one. Every later
  UNHANDLED raise then longjmps into it and the process dies at rip=rsp=rbp=0
  printing nothing. Twenty-one hand-written shapes of the same family all come
  out clean at HEAD, and so does the real `bindings.load` called from a
  three-line program, so the reduction is NOT the Python shape on its own.
track: A
type: bug
prio: 70
owner: frank-user
status: open
---

## What is measured, and what is not

Measured, `-g -O2` build of the demo at 82e070429, gs_base 0x1080fa0 so the
slot is at 0x1080fe0:

| where | rsp | EXC_TOP | reading |
| --- | --- | --- | --- |
| app.py:780, before the call | 0x7fffffff9290 | 0x7fffffff9290 | a live frame in App.create |
| app.py:784, after it | 0x7fffffff9290 | 0x7fffffff8760 | a frame 0xb30 below rsp |

`EXC_TOP == rsp` at every one of six independent samples, in four different
functions -- the frame is PUSHED, so that equality is the signature of being
inside a live try, and a value below rsp is the signature of a dead one.

NOT measured, and this is the part to distrust first: **the line attribution.**
Stepping through `bindings.py` reported lines in the order 596, 577, 596, 570,
583, 579 for straight-line code, so "the leak is in the statement at line 780"
rests on two breakpoints either side of a region whose interior numbering is
demonstrably scrambled. The bracketing is sound; the naming of the callee is
not.

## What was ruled out

- `bindings.load` itself. The REAL function, imported from the REAL module and
  called from a three-line program -- with and without an enclosing try, with
  and without a live callable in `announce` -- leaves the chain intact.
- Twenty-one shapes of the family, each ending in an uncaught raise so a stale
  head is fatal: return/break/continue out of a handler, bare / `as e` / tuple
  handlers, `else` and `finally` arms, a return out of a `with` inside a try, a
  `with` around a try, a failing `open`, nested handlers, a raise that escapes
  a handler, a method, and the same through two call frames. All 21 exit 217
  with the diagnostic. The generator-inside-a-try shape is NOT covered -- the
  stackless generator refuses `yield` there -- and is the obvious gap.
- Threads. The leak happens at app.py:780, before the loader thread starts, and
  each thread has its own TLS block (measured: thread 2's gs_base is its own
  and its slot 8 points into its own stack).

## Why it matters more than one demo

The failure mode is that a program **loses its diagnostics**: after the leak,
every unhandled exception is a bare SIGSEGV instead of a message. An enclosing
`try` hides it completely, so the same program looks fine everywhere a handler
happens to be in scope. The demo currently shows both faces -- some runs print
`TypeError: unsupported operand type(s) for -: 'set' and 'tuple'` (a real defect
of its own, racing with the loader thread), and some die silently at rip=0.

## Where to look next

The instrument that would settle it is a dynamic one, not another hand-written
shape: a `-d` define that logs every IR_EXC_ENTER / IR_EXC_LEAVE with its
return address, so the unmatched enter names itself. That does not exist. The
static half is cheap and worth doing first: count enters against leaves per
path in the IR of every proc the startup touches (`PXXDBG=a.ir:<proc>` dumps
one at a time), because the balanced 3-enter / 6-leave shape of `load`'s own
IR is what ruled it out and the same check over its callees has not been run.

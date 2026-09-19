---
slug: bug-a-something-in-lekkerzeilen-s-startup-still-leaves-an-exception-frame-on-the-chain
title: something in lekkerzeilen's startup still leaves an exception frame on the chain
summary: >
  DOES NOT REPRODUCE AT HEAD, and the environment it was measured in cannot be
  rebuilt; closed with its producer never named. Measured 2026-09-19 at pxx
  0f7b946e8b2e against lekkerzeilen 01d0fec (plus the blocker-01 workaround),
  `--shot`: TLS_SLOT_EXC_TOP equals rsp before app.py:780, after it, and at 784,
  and 4 of 4 runs end in a PRINTED diagnostic. A dead frame is still produced
  by any jump that crosses a protected region without IR_EXC_LEAVE / ENTER; the
  third such route, `goto`, is now refused as FPC refuses it. The unwinder's
  stale-frame walk no longer faults on a dead frame's link. What it still
  cannot see is a dead frame whose memory survived intact -- that one is jumped
  into as if live -- so a silent rip=0 death, or the line "a stale handler
  frame", is the signature that reopens this.
track: A
type: bug
prio: 70
owner: frankB
status: done
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

## 2026-09-14 — the demo no longer shows the silent face

Not a fix and not a reduction; a dated observation that narrows where to look,
and a warning about what it does NOT mean.

At 80840e14f plus the `pylib` one-sided-dunder fix, `--open-water` under
`setarch -R` runs past the startup this ticket measures, opens the window,
reaches the frame loop and dies with a PRINTED diagnostic:

```
Unhandled exception: TypeError: dict.update expects a mapping or an iterable of pairs
```

rc=217, not rip=0. So on this path the exception chain was intact by the time
the frame loop raised — which is the good face this ticket says the demo shows
some of the time, observed after several fixes landed in between
(`c53d9ab55` set-comp over-release, `eb9228950` star-argument over-release,
`bf4f94878` the literal splice, and today's dunder one).

**This is not evidence the leak is gone**, and reading it that way is the
mistake this ticket exists to prevent: the ticket's own text records that the
demo shows both faces, and one clean run of one entry point samples a single
path. The refcount fixes in between are the more interesting candidate — an
over-release corrupting a block the exception machinery walks would produce
exactly a chain that is sometimes right — but nothing here establishes that
either. What the run DOES retire is "the silent face is what you always get
now": it is not, on this path, today.

Re-measure with the gs_base / EXC_TOP probe at app.py:780 before treating any
of this as a state change.

## 2026-09-19 — re-measured at HEAD: gone on this path; the goto route closed

frankB. Not a reduction of the original -- that environment is gone -- but a
dated measurement plus the sibling the 82e070429 grep found.

**HEAD.** pxx 0f7b946e8b2e (source 94620a104), `-g`, default -O, `--threadsafe
-dSDL_DISABLE_IMMINTRIN_H -dGL_GLEXT_PROTOTYPES`, lekkerzeilen 01d0fec in a
scratch copy with `self.chart_view: float = chart.VIEW` (blocker 01), `--shot`
under SDL_VIDEODRIVER=wayland. gs_base 0x111b828, slot +0x40:

| where | rsp | EXC_TOP |
| --- | --- | --- |
| app.py:780 (pc 0xd2e04b) | 0x7fffffff70f8 | 0x7fffffff70f8 |
| app.py:781 (pc 0xd2e1cc) | 0x7fffffff70f8 | 0x7fffffff70f8 |
| app.py:784 (pc 0xd2e243) | 0x7fffffff70f8 | 0x7fffffff70f8 |

Four runs (one under gdb, three plain) all end rc=217 with
`Unhandled exception: AttributeError: 'str' object has no attribute 'delete'`
-- lekkerzeilen-7a's current blocker, a real error, reported. None printed the
stale-frame line.

**Why not bisect.** The pxx side is recoverable (a scratch tree at 82e070429
seeded from HEAD converges, 8a947b659a29) but the PROGRAM is not: the ticket was
measured on an uncommitted lekkerzeilen tree. Three pairings were tried and each
failed on a different skew: HEAD lekkerzeilen dies at app.py:745 under the old
compiler before reaching 780 (`'App' object has no attribute 'chart_view'`);
9521e53, the last commit before 09-14, still imports ctypes; 9ed69ed, the first
with the pxx backend, passes `print` as a value, which the old compiler refuses.

**The sibling (grep of the 82e070429 fix).** The three IR_EXC_ENTER sites are
each paired with a codegen depth, and exit/return/break/continue all unwind
through IRLowerCleanupToDepth. `goto` does not: AN_GOTO is a bare IR_JUMP, so a
goto out of a `try` left the frame on the chain (measured: the next unhandled
raise segfaults) and one into a `try` popped a frame never pushed. FPC refuses
both ("Jump in or outside of an exception block"); pxx now does too, at the
goto's own line, via a region id pushed with every region (IRPushExcRegion, now
the one place a region is opened). Not lekkerzeilen's producer -- NilPy has no
goto -- but the same class by a third route.

**The detector's walk.** b00ffe7b3's validation skips a head whose saved rsp is
not its own address, and then followed the dead frame's LINK, which is dead
memory too: on the goto repro it read 0x20 and faulted, so the process died
after the skip message and before "Unhandled exception". The walk now follows a
link only when it points up; otherwise it ends on the unhandled path, which
prints. Pinned by `test/test_unwinder_skips_a_dead_frame.pas`, built with the
new fault injection `PXXDBG=a.gotocross` (exact topic, not `all`); pin v412
segfaults on it.

**What is still invisible, and why it stays that way.** A dead frame whose
memory is untouched still passes the equality, so the unwinder longjmps into
it: measured with the dead frame 8 KB below the raise, both pin and HEAD die
silently. A position test ("live frames sit above the raising rsp") would catch
it and is UNSOUND: a stackful generator links its chain to its resumer's, and
the heap arena and thread stacks are both mmap'd, in either order. So the only
defence for that shape is not producing the frame.

Inert under `$(PXX_STABLE)` until the next pin (v412 predates all of it).

## Log
- 2026-09-19 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

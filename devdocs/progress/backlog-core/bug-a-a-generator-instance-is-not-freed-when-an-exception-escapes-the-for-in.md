---
track: A
prio: 55
type: bug
blocked-by: []
summary: "MEASURED on BOTH forms. Stackless: a generator instance leaks ~0.99 blocks per raise when an exception escapes the driving `for..in` -- SlFree lives in the loop teardown and the unwind skips it. Stackful: the same skipped teardown loses CoFree, so each escaping raise leaks the coroutine's 64 KB stack (RSS slope 4.59 kB/raise) plus the instance. Flat when the loop exhausts normally, and a plain non-generator raise+catch is flat at live=2, so it is neither the exception object nor generators in general -- it is the loop teardown on the unwind path only."
status: open
---

# A generator instance is not freed when an exception escapes the for-in

- **Track A.** Measured 2026-09-04 by frankb-78 as the residual of
  `bug-a-a-generator-body-raising-past-a-managed-temp-is-not-covered-by-the-unwind-landing-pad`,
  which closed the TEMP half of the same program's leak and left this.

## The measurement

`Once` (a `try` around `for x in Gen(1)`, `Gen` a `generator; stackless;` that
yields once then raises) called N times, `-dPXX_ALLOC_CENSUS`, live at the last
census threshold. Slope, not the raw count.

| raiser body | N=2000 | N=8000 | slope |
| --- | --- | --- | --- |
| `raise Exception.Create(gmsg)` — no temp | 1901 | 7815 | **0.986 / raise** |
| `Length(gmsg + Chr(65)) = 0` — no raise, loop exhausts | 3 | 2 | **flat** |
| plain `raise` + `except`, no generator at all | 2 | 2 | **flat** |

Row two says the instance IS freed when the loop ends normally. Row three says
the exception object itself is freed. So what leaks is the instance, and only
when the unwind takes the loop's teardown out of the path.

## Where it is

The `for..in` desugar builds `SlFree(__g)` and runs it at the end of the loop
(`pasparser_stmt.inc`, the `callFree` node). An exception raised inside the
generator body — or inside the loop body — propagates past that statement to
the enclosing handler, and the free never runs.

The generator INSTANCE is a heap block, so this is a plain block leak, not a
managed-value one: the fix is a frame-scoped free, not an ARC arm. The natural
shape is the one the rest of the compiler already uses for exactly this —
give the desugar's scope a managed local holding the instance, so the existing
proc cleanup frame / landing pad releases it on the unwind path, rather than
teaching the unwind about `SlFree` specifically.

## The guard this needs

The first row above, as an `assert_no_leak` row with a tight bound. Note that
`test/test_generator_raise_past_managed_temp.pas` already carries this leak in
its own numbers and says so — its bound is 3000 rather than 50 *because* of
this ticket, and tightening that bound is part of closing this one.

## The stackful form has it too, and it is far bigger — measured 2026-09-04

This said "UNCHECKED, not does-not-happen" because a stackful raise killed the
process before anything could be measured. That blocker is now fixed
(`bug-a-an-exception-raised-in-a-stackful-generator-body-does-not-reach-the-for-in-handler`),
and the leak underneath it is worse than the stackless one:

| N escaping raises | max RSS |
| --- | --- |
| 2000 | 9324 kB |
| 8000 | 36844 kB |

**4.59 kB per raise**, and that is the TOUCHED PAGES — the reservation is
`CO_STACK = 65536` bytes per generator, so the address space lost is 64 KB per
escaping raise, not 4.6. Same cause: `CoFree` (which frees the heap stack AND
the instance) is in the loop teardown the unwind skips.

So the fix wanted here covers both forms and the stackful one is the reason to
do it: a program that raises out of a stackful generator in a loop grows by
64 KB a time. `test/test_generator_stackful_raise_reaches_the_handler.pas` runs
N=5 for exactly this reason and says so.

## Still not known

Whether the same skipped teardown loses anything else — the for-in desugar's
`SlFree` / `CoFree` are what this ticket names, and nobody has walked the rest
of that teardown asking the same question.

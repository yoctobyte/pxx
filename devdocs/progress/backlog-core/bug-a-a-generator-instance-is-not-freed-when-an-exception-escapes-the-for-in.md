---
track: A
prio: 55
type: bug
blocked-by: []
summary: "MEASURED: a stackless generator's instance leaks ~0.99 blocks per raise when an exception escapes the driving `for..in` — SlFree lives in the loop teardown and the unwind skips it. Flat (live=2) when the loop exhausts normally, and a plain non-generator raise+catch is flat at live=2 too, so it is neither the exception object nor the generator in general: it is the loop's teardown on the unwind path only."
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

## What is NOT known

Whether the same hole exists for a **stackful** generator. It could not be
measured: an exception raised inside a `generator;` (non-stackless) body does
not reach the driving `for..in`'s handler at all — it goes unhandled and kills
the process. That is filed separately as
`bug-a-an-exception-raised-in-a-stackful-generator-body-does-not-reach-the-for-in-handler`.
UNCHECKED, not "does not happen".

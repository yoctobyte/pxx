---
track: A
prio: 55
type: bug
blocked-by: []
summary: "FIXED, and it took two fixes. The for-in generator desugar ran its teardown (SlFree / CoFree) as a TRAILING STATEMENT, so an escaping raise, an `exit` or a `break` walked past it -- 0.936 blocks/raise stackless, the whole 64 KB CO_STACK per raise stackful. It is a FINALIZER now, the shape the class-enumerator for-in in the same file always used. That alone did not fix `exit`: IRLowerCleanupToDepth never marked the finally body as a statement, so a finalizer that is a bare CALL node was not emitted at all on the exit/break/continue paths -- invisible to any hand-written probe, because a source try/finally always arrives as an AN_SEQ. All four rows flat now. RESIDUAL, measured not assumed: a stackless consumer that YIELDS inside the loop keeps the trailing free (SLCheckEligible rejects a yield inside try/finally), leaking 0.999 instances per escaping raise; closing that is the same job as lifting `yield inside try is not allowed (v1)`."
status: done
owner: frankb-78
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


## Fixed 2026-09-04 by frankb-78 — and it took two fixes, not one

**The teardown is a finalizer now.** `GenForInGenTeardown` in
`pasparser_stmt.inc` wraps the loop in `AN_TRY_FINALLY` with the free as the
finalizer, for both the stackless (`SlFree`) and stackful (`CoFree`) arms. That
is the shape `ParseForInEnumeratorAST` two functions down has always used for
its enumerator's `Free`; the two generator arms were the ones that did not.

| row | before | after |
| --- | --- | --- |
| stackless raise escapes the for-in | 0.936 blocks/raise (1805 @2000, 7419 @8000) | FLAT, live=2 at both |
| stackful raise escapes the for-in | 4.40 kB RSS/raise (9068 kB @2000, 35436 kB @8000) | FLAT, 392 kB at both |
| `exit` out of the loop | 1.0 blocks/call, `frees=0` | FLAT, live=2 |
| `break` out of the loop | same | FLAT, live=2 |

## The second fix, and why three green probes hid it

Wrapping alone did **not** fix `exit`. The IR was right —
`exc_leave; load; arg; call SlFree; terminate` — and the free still did not
happen. The tell was in the dump: the normal-path and handler-path calls carried
`ival=1` and the exit-path call carried `ival=0`.

`IRLowerCleanupToDepth` (the path an `exit`, `break` or `continue` takes out of
a try/finally) lowered the finally body and **never called
`IRMarkStatementNode`**, while both arms of the `AN_TRY_FINALLY` lowering did.
An unmarked `IR_CALL` is "an expression someone wants the value of", and a call
whose result nothing consumes is not emitted. So the finalizer was silently
dropped on the early-exit paths only.

**A source-level `try ... finally F; end` cannot show this**, because
`ParseTryStatementAST` always hands over an `AN_SEQ` and sequence lowering marks
its own statements. Only a DESUGAR passing a single call node directly reaches
it. Three probes measured GREEN before the real cause was found — `exit`,
`break` and `continue` past a **value-returning** finalizer — because all three
were written in Pascal source and all three therefore got the SEQ.
**The population was "try/finally with an early exit"; the defect lives only in
the compiler-generated corner of it, and every hand-written probe is outside
that corner by construction.**

## What is NOT fixed, measured rather than assumed

**A stackless consumer that yields inside the loop keeps the trailing free.**
Inside a stackless generator the wrapped `yield` would sit in a try/finally, and
`SLCheckEligible` rejects exactly that ("yield only allowed at top level or
inside for/while/if/case") because the flattener has no arm to split a state
machine across a finally frame — the same v1 restriction that rejects a source
`try` around a `yield`. Wrapping unconditionally turned
`for v in Inner(n) do yield v * 10` from working code into a **compile error**.
So `GenForInGenTeardown` guards on `CurProcIsStackless and SLHasYield`.

Measured residual for that shape: **0.999 instances per escaping raise** (live
1929 @2000, 7923 @8000). It is exactly one — the OUTER instance is freed now and
the INNER one is not. Deliberately **not** in
`test_generator_instance_freed_on_escaping_raise.pas`: including it would force
that program's bound from 50 up into the thousands, and a guard sized around a
leak next door cannot see its own come back.

Closing it means teaching the stackless flattener to cross a finally frame,
which is the same job as lifting `yield inside try/except/finally is not allowed
(v1)`. That is a feature, not this bug. Note the guard is `CurProcIsStackless`,
not `CurProcIsGenerator`: a **stackful** consumer that yields inside the loop is
fine, because `CoSwitch` saves and restores `BSS_EXC_TOP` per context.

## Guards

`test/test_generator_instance_freed_on_escaping_raise.pas` (new): five rows —
stackless raise, stackful raise, `exit`, `break`, and `nest`, the
must-not-move row that fails as a COMPILE ERROR if the wrap is ever made
unconditional. `assert_no_leak` at bound **50**; `expect_same` returns 0 on the
pre-fix binary for every row, which is the point — only the census separates
them. Positive control on HEAD-before: `live=8002` against the bound of 50.

`test_generator_raise_past_managed_temp.pas`'s bound tightened **3000 -> 50**
(it was sized around this ticket's leak) and its header corrected; positive
control on HEAD-before: live=1805.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

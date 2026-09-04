---
track: A
prio: 30
type: refactor
blocked-by: []
status: backlog
summary: "Every program with a `for .. in` now pulls the exception runtime -- measured +4096 bytes of stubs on x86-64, xtensa and riscv32 alike, including a program whose only for-in is over an array and which cannot raise. Correct but over-broad: only the class-enumerator and generator forms synthesise a try/finally, and a TOKEN pre-scan cannot tell them from `for c in s` without the symbol table. Narrowing needs a post-parse emission point for the stubs, not a better guess in the scan."
---

# The for-in exception-runtime trigger is the whole token shape

Filed by frankb-78 immediately after the fix it describes, so the cost is on the
board rather than implied by a commit message.

## What it costs, measured

`test/test_forin_native.pas` — only native for-in (array, string, enum, set), no
`try`, nothing that can raise:

| target | pin v403 | HEAD |
| --- | --- | --- |
| x86-64 | 114456 B | 118552 B |
| xtensa | 294764 B | 298860 B |
| riscv32 | 364396 B | 368492 B |

**+4096 bytes on every target**, and it is the same 4096 because it is the same
stub set. On a small ESP program that is the difference that matters most.

## Why it is the whole shape

Two `for .. in` forms synthesise a try/finally: the class-enumerator form wraps
its enumerator's `Free`, and the generator form wraps `SlFree` / `CoFree`. The
native forms (array, string, set, enum range) wrap nothing.

The stubs are code, and code emitted after the body has started lands inside it,
so the decision must be made before parsing — in `ParseProgram`'s token
pre-scan. At that point `for x in c` and `for c in s` are the same tokens; which
one wraps depends on what `c` IS, which needs the symbol table. So the scan
triggers on the shape and over-approximates.
See `bug-a-a-generator-instance-is-not-freed-when-an-exception-escapes-the-for-in`
for how the under-approximation failed (`call 0`, a build error on every target).

## The shape of a fix

Not a better pre-scan — the information is not there. What is needed is an
emission point for the exception stubs that is reachable AFTER parsing, so
`EnableExceptionRuntime` can be called from the desugar that actually needs it.
The stubs are reached only by `call`, so a region reserved before the body and
filled at the end would do it; the same move would retire the `class operator
Finalize` token trigger, which exists for exactly this reason and has the same
over-approximation (any declaration of that operator, used or not).

**Three synthesised-try sites now depend on a token guess.** That is the
argument for the refactor, not the 4 KB.

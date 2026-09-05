---
slug: decide-should-a-c-main-exist-on-the-esp-profile-at-all
track: S
type: decide
prio: 35
status: open
found: 2026-09-05
found-by: frankC
owner: frankS
blocked-by: []
summary: "A C program with a `main` refuses on xtensa's DEFAULT and BARE profiles: `C program entry stub on xtensa: hosted linux only. On the ESP profile there is no argc on the stack to pass to main and no kernel to take the exit_group that ends it`. That is a DELIBERATE guard and a correct statement, and the question it leaves open is a design one, not a bug: should a C `main` exist on a profile where FreeRTOS gives tasks rather than processes, and if so what does it mean? Split out of bug-c-including-stdio-h-refuses-to-compile-for-xtensa, whose measurable claim is now false — the posix profile compiles `#include <stdio.h>` plus `main` at 660016 B with NO --xtensa-long-calls and RUNS. Filed against frankS as the residual owner: this is the ESP profile's semantics, not the C frontend's."
---

# Should a C `main` exist on the ESP profile at all?

Not a defect report. `bug-c-including-stdio-h-refuses-to-compile-for-xtensa`
resolved today because everything measurable in it is now false, and CLAUDE.md
says an exculpation needs an owner for the residual question. This is the
residual.

## What is measured, compiler `1359b156f797`

```
--platform=posix   #include <stdio.h> + main   660016 B   links, and RUNS ("hello")
default / bare     same source                 refuses at the C entry stub
```

The posix half needed `--xtensa-long-calls` until `f49c0e11f` reserved the wide
call form unconditionally for `FiniRunnerProc`. It does not any more. **Every
C-on-xtensa number taken after `f49c0e11f` is flag-free.**

The refusal on the other two profiles is not that. It is a guard someone wrote
on purpose, and its message is the argument:

> no argc on the stack to pass to main and no kernel to take the exit_group
> that ends it

## The question

CLAUDE.md: **ESP is not a Unix.** FreeRTOS gives tasks, not processes, and 33
PAL entries refuse deliberately so POSIX-shaped code meets
`PAL_ERR_UNSUPPORTED` rather than a wrong answer. `main` is POSIX-shaped in
exactly that way: it takes an argument vector nobody supplies and returns an
exit status nobody collects.

So the fork is:

1. **Keep refusing.** `main` has no meaning here; a C program for this profile
   should spell its entry point the way the platform does. The current message
   already says this well.
2. **Accept `main` with defined ESP semantics** — `argc = 0`, `argv = NULL`,
   and a return that ends the task rather than the system. That makes ordinary
   C source portable to the profile, at the cost of a `main` that means
   something different from the one on every other target.

**This is a Track U-shaped question living in S's lane**, and it is deferred to
whoever owns the profile's semantics rather than guessed at by the C frontend.

## What is NOT in scope here

The C frontend side is fine and measured: the entry stub exists for xtensa
(`233e693bb`), varargs are correct there once the target joined the 4-byte
slot set, and `tools/c_va_arg_every_target.sh` asserts a refusal on this target
must name this stub — so if the answer is (2), that script's xtensa row flips
from "refuses" to "builds and must match gcc" and will say so.

---
slug: decide-should-a-c-main-exist-on-the-esp-profile-at-all
track: S
type: decide
prio: 35
status: decided
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

## DECIDED — the fork dissolves: it conflates two output modes (frankS, 2026-09-05)

**Neither option. A C `main` already exists on the ESP profile, on the only
output mode the profile can actually use.** Measured at `8cefbbd4fa69`
(`converged after 1 round(s)`):

| target | profile | source | standalone ELF | `--emit-obj` |
| --- | --- | --- | --- | --- |
| xtensa | default | `int main(void)` | refused | **BUILDS**, entry GLOBAL `app_main` |
| xtensa | default | `void app_main(void)` | refused | **BUILDS**, entry GLOBAL `app_main`, user's stays LOCAL |
| xtensa | `--esp-profile=bare` | `int main(void)` | refused | **BUILDS**, entry GLOBAL `app_main` |
| xtensa | `--esp-profile=bare` | `void app_main(void)` | refused | **BUILDS** |
| xtensa | `--platform=posix` | `int main(void)` | BUILDS | — |

**`--emit-obj` is how C ships to an ESP32** — the IDF links your object and
calls `app_main` — and it needs no entry stub at all, so the guard this ticket
is about never runs on that path. The semantics option 2 proposed inventing are
already implemented and already measured: the entry stub runs the initialisers
and calls your entry, and the writer exports it under the name the IDF calls.

**Option 1 was not available either, and that is the part worth recording.**
`void app_main(void)` — the platform's own spelling, the thing "let a C program
spell its entry point the platform's way" means — is refused by the standalone
path with the *identical* message, one that argues from `argc` and `exit_group`.
`app_main` takes no argc and returns no status. **The diagnostic was correct
about `main` and fired on a source it did not describe.**

So both options were about a path nobody ships on, while the path everyone
ships on had already answered the question.

## What was actually wrong, and it is fixed

Not the refusal — the refusal is right, and a standalone ELF on bare metal
genuinely has no kernel to take an `exit_group`. **The message read as "C has no
entry point on ESP"** when the truth is "C has no entry point in a standalone
ESP *executable*, and the mode you want is `--emit-obj`." A correct refusal that
does not name the working alternative sends the reader to file a design ticket,
which is exactly what happened here.

The diagnostic now names the mode, says it works on this profile today, and says
what the entry is exported as. `cparser.inc` carries the measurement beside the
guard so the next reader does not re-derive it.

**Positive control on the fix, both directions:** the standalone build still
refuses (the guard is not weakened), and the `--emit-obj` build the message
points at was re-run afterwards and still exports `GLOBAL app_main`. A message
naming a path nobody checked would be the same defect one layer up.

## Residual, and it is small

`tools/c_va_arg_every_target.sh` asserts a refusing target refuses *at the C
entry stub* (frankC, tonight). That assertion is still true and unchanged — the
standalone path still refuses there. **The script does not cover `--emit-obj`**,
which is the mode that works, so nothing in the suite would notice if that path
regressed. That is a coverage gap rather than a defect; frankC owns the script
and it is one row, not a redesign.

## Log
- 2026-09-05 — decided; this names the commit that carried the decision, which is not always the one that carried the change — commit 2beb2abec.

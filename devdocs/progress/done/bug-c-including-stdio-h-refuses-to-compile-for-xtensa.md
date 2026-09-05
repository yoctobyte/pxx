---
slug: bug-c-including-stdio-h-refuses-to-compile-for-xtensa
track: C+S
prio: 45
type: bug
status: done
blocked-by: []
owner: ""
created: 2026-09-01
found-by: frankA (incidentally, while fixing @external on i386)
summary: "RESOLVED 2026-09-05 (frankC): re-measured at HEAD and nothing this ticket claims is true any more. `#include <stdio.h>` plus a `main` on xtensa under --platform=posix compiles at 660016 B with NO --xtensa-long-calls and RUNS -- the blocked-by half was closed by frankS's f49c0e11f, which reserves the wide call form unconditionally for FiniRunnerProc. The originally stated symptom (`__pxx_read is a pxx-internal runtime symbol`) was already recorded as unreachable. THE ONE THING LEFT IS NOT A BUG: under the default and bare profiles a C `main` refuses at the entry stub deliberately, because there is no argc on the stack and no kernel to take the exit_group -- a design question about what `main` means where FreeRTOS gives tasks rather than processes. Split out as decide-should-a-c-main-exist-on-the-esp-profile-at-all, owner frankS."
---

# `#include <stdio.h>` does not compile for xtensa

```c
#include <stdio.h>
int f(int a){ return a+1; }
```

| target | result |
| --- | --- |
| x86-64 | `ok: [code=234076B ...]` |
| xtensa | `error: __pxx_read is a pxx-internal runtime symbol and cannot be imported dynamically` |

The error names `lib/crtl/src/unistd.c`, `near: ssize_t write`. A file with no
`#include` at all compiles for xtensa (107 bytes, 1 proc), so the xtensa C path
works — it is reaching crtl that breaks.

## What the guard is telling us

The message is not wrong: `__pxx_read` has no library exporting it, so importing
it dynamically would link clean and die at load. It asks for "a missing `uses` of
the unit that defines it, or a C translation unit compiled without its Pascal
bridge". On x86-64 that bridge is evidently visible and on xtensa it is not —
which makes the interesting question *what supplies `__pxx_read` per target*,
not *why is the guard firing*.

Worth checking against the S lane's standing note that ESP is not a Unix: 33 PAL
entries refuse deliberately, so it is possible the intended xtensa answer is that
`read`/`write` route through the PAL rather than through a Pascal bridge, and
that the crtl source simply has no xtensa arm. If so the fix is an arm, not a
missing `uses`, and this ticket is S-flavoured rather than C-flavoured.

**Not the same as** `bug-c-a-header-reached-by-uses-discards-function-bodies-and-imports-them-instead`,
which shares the "became an external" shape but is about a `static` defined in a
`.h` and reproduces on x86-64. This one is target-conditional, which that one is
not.

## Re-measured 2026-09-05 (frankS)

`#include <stdio.h>` + `int main(void){return 0;}`, one file, every profile:

| configuration | result |
| --- | --- |
| x86-64 (control) | compiles, `code=311064B` |
| `--target=xtensa` (default) | C entry stub refuses: hosted linux only |
| `--target=xtensa --esp-profile=bare` | same entry-stub refusal |
| `--target=xtensa --platform=posix` | CALL0/CALL8 wall at `__pxx_run_finalizers` |
| ...`--platform=posix --xtensa-long-calls` | **compiles**, `code=647020B` |

The original error does not appear in any of them. It was reduced away by
`e6fd258d8` and its neighbours rather than by anything aimed at this ticket,
which is why the ticket never moved.

**Do not close this on the reduction.** The residual is real and has an owner
now: the posix path is [[feature-a-xtensa-should-not-need-a-flag-to-build-a-large-image]],
entered as `blocked-by`. The entry-stub refusal for a C `main` under the ESP
profile is a separate question and nobody owns it — it may well be correct.

## 2026-09-05 (frankC): re-measured at HEAD, and nothing this ticket claims survives

Compiler `1359b156f797`, no flags beyond the profile:

```
--platform=posix   #include <stdio.h> + int main   660016 B   links, and RUNS ("hello")
```

**No `--xtensa-long-calls`.** The blocked-by half is gone: `f49c0e11f`
(frankS, tonight) reserves the wide call form unconditionally for
`FiniRunnerProc`, which is the callee the CALL0/CALL8 wall was reached through.
The `blocked-by` edge has been removed by its owner.

The stated symptom — `__pxx_read is a pxx-internal runtime symbol` — was
already recorded as unreachable earlier today. So all three readings of this
ticket are now false: the original one, and both of the two "other ways" the
09-05 summary substituted for it, except one.

**The exception is not a bug and it is not mine.** Under the default and bare
profiles a C `main` still refuses at the entry stub, deliberately, with a
message that is a correct statement about the platform: no argc on the stack,
no kernel to take the exit_group. That is a design question about what a C
`main` means where FreeRTOS gives tasks rather than processes.

Filed as [[decide-should-a-c-main-exist-on-the-esp-profile-at-all]], owner
frankS, rather than left inside a resolved ticket where nobody would find it.
An exculpation needs an owner for the residual question.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

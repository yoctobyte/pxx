---
slug: bug-c-including-stdio-h-refuses-to-compile-for-xtensa
track: C+S
prio: 45
type: bug
status: new
blocked-by: ["feature-a-xtensa-should-not-need-a-flag-to-build-a-large-image"]
owner: ""
created: 2026-09-01
found-by: frankA (incidentally, while fixing @external on i386)
summary: "STATED SYMPTOM IS UNREACHABLE AT HEAD, re-measured 2026-09-05. The `__pxx_read is a pxx-internal runtime symbol` refusal still exists (symtab.inc:13982) but nothing reaches it from this file in any profile. `#include <stdio.h>` plus a `main` now fails two OTHER ways: under the default and bare profiles the C entry stub refuses outright ('hosted linux only -- no argc on the stack and no kernel to take the exit_group'), which is a deliberate guard; under --platform=posix it hits the CALL0/CALL8 +-512 KiB forward-call wall and compiles cleanly with --xtensa-long-calls. Both are true statements and neither is the one this ticket was filed on. The posix half is the blocked-by; the entry-stub half is a separate design question about C main on the ESP profile."
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

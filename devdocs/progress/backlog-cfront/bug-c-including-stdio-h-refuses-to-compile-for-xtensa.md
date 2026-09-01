---
slug: bug-c-including-stdio-h-refuses-to-compile-for-xtensa
track: C+S
prio: 45
type: bug
status: new
blocked-by: []
owner: ""
created: 2026-09-01
found-by: frankA (incidentally, while fixing @external on i386)
summary: "`#include <stdio.h>` refuses to compile for --target=xtensa: `__pxx_read is a pxx-internal runtime symbol and cannot be imported dynamically`, raised in lib/crtl/src/unistd.c at `ssize_t write`. The identical two-line file compiles for x86-64. Reduced to `#include <stdio.h>` plus one trivial function -- nothing in the user code touches read/write. A C file with NO include compiles for xtensa fine, so this is the crtl pull, not the xtensa C backend generally. The guard is correct in what it says (the symbol needs a Pascal bridge that is not visible); what is target-specific is why the bridge is missing on xtensa and present on x86-64."
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

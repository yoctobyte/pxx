---
slug: bug-c-a-thread-declaration-that-does-not-fit-the-tls-area-becomes-a-shared-global-with-only-a-warning
title: "a C `__thread` that does not fit the per-thread area silently becomes ONE copy shared by every thread — the identical Pascal declaration is refused"
type: bug
track: C
prio: 50
status: new
created: 2026-09-19
found-by: frankS
tags: [tls, threadvar, cfront, silent-wrong-value, diverging-policy]
blocked-by: []
summary: "TryAssignThreadVarStorage is ONE allocator with TWO refusal policies, and C got the dangerous one. When a thread-local does not fit the per-thread variable area, Pascal's arm (AssignThreadVarStorage) raises an Error and the compile fails; C's arm emits a WARNING and gives the declaration a single process-wide copy, and the program compiles, links and runs. Measured 2026-09-19 with `__thread int counter;` at -dPXX_TLS_USER_0: `warning: __thread counter: the per-thread variable area is full (0 bytes)... this declaration therefore gets ONE copy shared by every thread, not one per thread ... threaded code will read and write another thread's value with no further warning`, then `ok:` and a working single-threaded binary. The warning is accurate and says exactly what will go wrong; what makes this a bug rather than a documented limit is that it is a COMPILE-TIME warning about a RUNTIME data race in a program that otherwise behaves, so it survives a green build and a passing single-threaded test suite. The divergence is deliberate -- TryAssignThreadVarStorage's own comment says the C frontend reaches the same allocator and does not Error -- so this ticket is about whether that choice is still right, not about an oversight. NOT URGENT AND NOT REACHABLE TODAY BY ACCIDENT: the area is 3,072 bytes by default, so a C program needs ~768 ints of thread-local storage, or an explicit -dPXX_TLS_USER_0/_1K, to get here. It becomes reachable the moment anyone lowers the default or extends the zero-area prescan to C."
---

# How it was found

While deciding whether the threadvar-area prescan
(`feature-a-the-threadvar-area-is-3072-bytes-of-bss-in-every-program-that-has-no-threadvar`)
could give C programs a zero-byte area the way it now does for Pascal and NilPy.
It cannot, and this is why: the NilPy arm is safe **because** a threadvar on its
ambient Pascal chain is refused loudly, with the flag to raise named in the
message. C has no such backstop.

# The measurement

```c
#include <stdio.h>
__thread int counter;
int bump(void) { counter += 7; return counter; }
int main(void) { counter = 0; printf("got=%d\n", bump()); return 0; }
```

| build | outcome |
| --- | --- |
| default area (3,072 B) | `ok:`, `got=7`, one copy per thread — correct |
| `-dPXX_TLS_USER_0` | **`warning:`**, `ok:`, `got=7` — one copy for the process |

and the same shape in Pascal at `-dPXX_TLS_USER_0` is
`error: threadvar counter: the per-thread variable area is full (0 bytes)`,
exit 1.

# The fork, stated as a goal and not as a mechanism

**Do we want a C program whose thread-locals do not fit to fail to build, or to
build and be wrong only when it uses threads?**

Arguments for keeping the warning: C's `#include`s mean a `__thread` can arrive
from a header the author never opened, so an Error can refuse a program over a
declaration that is never used by any thread; and single-threaded C is the
common case.

Arguments for the Error: it is the answer Pascal already gives for the identical
mistake, the message already names the flag that fixes it, and the failure it
prevents is a data race — the class this project pays the most for. A warning in
a build that prints `ok:` and hundreds of other lines is not a control.

A third option nobody has costed: Error only when the translation unit also
creates a thread, which is knowable at the same point the RTTI reader flag is.

# What must be true before this is closed

If the policy changes, the change is in `TryAssignThreadVarStorage`'s C arm in
`compiler/pasparser_decl.inc` and nowhere else — the allocator is one door and
the two policies are one `if`. Anything that adds a second refusal site is the
wrong fix.

# The pin cannot build ANY C program for i386 or arm32

- **Type:** bug (Track A — the pin is stale against `lib/crtl/src/fcntl.c`;
  the fix is a `make pin`, which is the owner's call, not an agent's)
- **prio:** 55
- **Status:** done
## Measured
`stable_linux_amd64/default/pinned` (pin v398, `4c4a5c125`, 2026-08-30) against
a program with no includes of its own:

```c
#include <stdio.h>
int main(void){ printf("hi\n"); return 0; }
```

```
             PXX_STABLE                                   compiler/pascal26
x86_64       OK                                           OK
i386         error: target i386: call argument count       OK
             mismatch (defaults not supported yet)
             in: lib/crtl/src/fcntl.c near openat
aarch64      OK                                           OK
arm32        error: target arm32: call argument count      OK
             mismatch  (note: no "defaults" clause)
riscv32      OK                                           OK
```

The current compiler builds all five, so this is pin-vs-tree skew and not a
regression in the tree. It is not the program's code: the failure is inside
crtl's own `fcntl.c`, on the variadic `openat` that every C program drags in
through the auto impl pull. Nothing a caller writes can avoid it.

riscv32 passing while arm32 fails, with a *different* error string, is worth a
look on its own — the two are both ILP32 and the arm32 message is missing the
`defaults not supported yet` clause, so they may not be the same defect.

## Why it matters
Track B/E's rule is "build with `$(PXX_STABLE)`, never rebuild the compiler."
For C aimed at i386 or arm32 that is currently impossible, and the failure
names a crtl file rather than the pin, so the first reading is that crtl is
broken. It is not.

frankD's busybox cross work reaches i386 and arm32 after aarch64, so this is on
that path.

## Not fixed here
The fix is `make pin`, which blocks every lane while it runs and is one of the
three things CLAUDE.md reserves for the owner. Filed rather than done.

## Resolved by pin v399 (`a7abc248116d62dfcbaac2fde198f21f860a435c`, 2026-09-01)

The owner cut v399 at `86c71828c`, and its commit message names this ticket as
one of the two reasons. Re-ran the ticket's own repro against the pin now on
disk (`stable_linux_amd64/default/pinned`, sha256 `954adef93a7b…`, which matches
the sha in the pin commit's subject line):

```
x86_64    OK
i386      OK
aarch64   OK
arm32     OK
riscv32   OK
```

All five, where v398 failed two. MEASURED against the new pin, not inferred from
the pin commit's claim — the pin's own gate is `stabilize-fast`, which does not
compile a C program for i386 at all, so nothing in that gate would have caught
it had the fix not actually been in the cut window. `fc9c8ade2` landed
2026-08-31T17:13Z and the cut is `86c71828c`, so it is.

Note for whoever hits the next instance of this SHAPE: nothing here was a tree
regression. The tree built all five throughout. This was pin-vs-tree skew, and
the only reason it was visible at all is that a `$(PXX_STABLE)` consumer tried a
cross target. A pin gate that does not cross-compile cannot see this class, and
`make stabilize-fast` is fast by design — so the guard is that Track B/E hit it
downstream, not that the pin catches it.

## Log
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit fa7ba3fc4.

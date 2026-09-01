# The pin cannot build ANY C program for i386 or arm32

- **Type:** bug (Track A — the pin is stale against `lib/crtl/src/fcntl.c`;
  the fix is a `make pin`, which is the owner's call, not an agent's)
- **prio:** 55
- **Status:** open

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

---
track: B
prio: 40
type: bug
---

# Calling `htons()` makes a C binary libc-dependent, losing the libc-free property

- **Type:** bug (crtl link behaviour) — **Track B** (`lib/crtl/src/socket.c`)
- **Found:** 2026-08-02 while adding the byte-order declarations to
  `<netinet/in.h>` ([[feature-crtl-libc-gap-batch-2026-08]]). **Pre-existing** —
  not introduced by that change.

## Measured

```c
#include <arpa/inet.h>            /* the OLD path, unchanged by anything today */
int main(void){ return (int)htons(1); }
```

| program | linkage |
| --- | --- |
| `htons` (or any other socket.c symbol) | **dynamically linked, NEEDED libc.so.6** |
| the same file without it | statically linked |
| a C program using only string/stdio/errno | statically linked |

True on every target (x86-64, i386, aarch64, arm32) and through both
`<arpa/inet.h>` and the newly-added `<netinet/in.h>` declarations, so it is a
property of pulling `socket.c` in, not of either header.

## Why it matters

The syscall-only core being libc-free is a design invariant — it is why
`-dPXX_DYNLIB_LIBC` exists as an *opt-in* for the loader, and why the ESP and
static-target stories work at all. A program acquires a glibc runtime dependency
here by calling a **pure byte-swap function**, which is about as far from
needing libc as a function gets.

The practical bite is portability, and it is not hypothetical: such a binary
cannot run under `qemu-aarch64`/`qemu-arm` on a box without a target sysroot,
which is exactly how it was noticed — a test calling `htons` could not be
cross-verified while the identical test without it could.

## Not yet diagnosed

`socket.c` declares only `__pxx_*` externs (`__pxx_socket`, `__pxx_bind_ipv4`,
…), which are Pascal-side helpers, not libc symbols — so *why* pulling this
translation unit in forces a `libc.so.6` NEEDED entry is unexplained. Worth
finding out before fixing: the honest answer might be that one of those helpers
resolves through a libc-linked path, in which case the fix is there and not in
`socket.c`.

Do not "fix" it by duplicating the byte-swaps somewhere else — that hides the
dependency for four functions and leaves it for every other socket symbol.

## Gate

A C program calling `htons` is statically linked, and
`test/cerrno_strings.c`-style cross-target runs work with the byte-order
assertions restored to it (they were removed precisely because of this).

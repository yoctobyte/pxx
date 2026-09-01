# crtl is not large-file safe at ILP32: off_t is 32 bits, so >2GB files are wrong

- **Type:** feature (Track A — `lib/crtl/include/sys/_types.h`,
  `lib/crtl/include/fcntl.h`, `lib/crtl/src/{fcntl.c,unistd.c,sys/mman.c}`)
- **prio:** 45
- **Status:** open

## The measurement
`gcc -m32 -D_FILE_OFFSET_BITS=64` against `pxx --target=i386`, same source,
`_GNU_SOURCE` set explicitly in the probe (feature-test macros change what the
headers declare — see frankD's note on the crtl-impl macro environment):

```
           glibc-m32   pxx-i386
off_t       8           4
sigset_t  128          64
```

`dev_t`, `ino_t` and `blkcnt_t` were the other three rows and are fixed —
`bug-a-stat-returns-st-dev-and-st-rdev-in-the-kernel-internal-encoding`.

## Why off_t is not a one-line widening
`lib/crtl/src/fcntl.c`'s header comment is correct today and would become false
the moment `off_t` moves: the `struct flock` a caller builds matches the
kernel's native layout on each target *because* `off_t == long`. Widening it
alone would make every `F_SETLK`/`F_GETLK` at ILP32 pass a struct the kernel
reads with the wrong field offsets — sqlite's whole locking protocol, failing
silently rather than erroring.

So the change is a group:
- `struct flock64` and `F_GETLK64`/`F_SETLK64`/`F_SETLKW64` (12/13/14 on i386)
- `lseek` → `_llseek` (offset split high/low, result through a pointer)
- `pread`/`pwrite` → `pread64`/`pwrite64`, offset as a register pair with the
  target's argument-alignment rule (arm32/riscv32 differ from i386)
- `mmap` → `mmap2`, offset in pages
- `off_t` in `struct stat` and every crtl signature that carries one

The PAL side is already `Int64` throughout, so nothing above the syscall layer
needs widening — this is entirely inside `lib/crtl`.

## Why it is worth doing
The 32-bit targets are the point of the cross axis, and a >2GB file is ordinary
— sqlite databases, a DOSBox disk image, a busybox `cp`. The failure mode is a
wrong offset, not a refusal.

## sigset_t
64 bits where glibc has 128. Internally consistent (crtl's own
`sigprocmask`/`sigaction` agree with each other) and never measured against the
kernel's `_NSIG/8` expectation. Cheap to check once someone is in this file:
`sigprocmask` with a signal above 32 is the row that would tell.

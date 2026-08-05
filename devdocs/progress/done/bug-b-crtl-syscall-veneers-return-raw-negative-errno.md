---
summary: "open/fsync/dup/dup2/chdir/symlink/link/pipe/mkdir/fchmod/utimes returned the kernel's raw negative errno instead of -1, and never set errno — so perror() after a failed open printed 'Success'"
type: bug
track: B
prio: 60
---

# crtl syscall veneers returned the raw negative errno

- **Type:** bug — Track B (`lib/crtl`)
- **Status:** done
- **Opened / closed:** 2026-08-05
- **Found by:** `tools/gcc_diff_probe.sh`, second case batch
  ([[feature-c-gcc-oracle-differential-probe]]).

## Symptom

```c
errno = 0;
int fd = open("/tmp/no_such_dir/x", O_RDONLY);
printf("%d %d\n", fd, errno);
```

| | fd | errno |
| --- | --- | --- |
| gcc | -1 | 2 (ENOENT) |
| pxx | **-2** | **0** |

`open("/", O_WRONLY)` returned **-21** (EISDIR) the same way.

Eleven functions across four files did this: `open`, `openat`, `creat`,
`open64`, `fcntl`, `fcntl64` (`fcntl.c`), `fsync`, `dup`, `dup2`, `chdir`,
`symlink`, `link`, `pipe` (`unistd.c`), `mkdir`, `fchmod` (`sys/stat.c`),
`utimes` (`sys/time.c`).

## Why it survived

The PAL deliberately returns the raw kernel convention — 0/positive, or a
negative errno — and most of `unistd.c` already translates it inline
(`if (rc < 0) { errno = -rc; return -1; }` appears a dozen times). The functions
added later were written as one-line forwards and simply skipped the step.

It hid because **`if (rc < 0)` catches both conventions**. That is how almost
all C code tests a syscall, so almost all C code kept working, and the failure
only shows in the two places that read the detail:

- `if (fd == -1)` — the other idiom, and it does not fire;
- `perror(...)` / `strerror(errno)` after the failure — prints **"Success"**,
  because errno was never touched.

So the program takes the error branch correctly and then reports the wrong
reason, which is the plausible-wrong-value shape this codebase treats as worse
than a crash.

`isatty` was the sharp one: it must answer 0 or 1, and a negative leaking out
makes every `if (isatty(fd))` interactivity check — colour, progress bars,
prompting — read TRUE. It happens to return 0 for a regular file today, but
nothing was stopping the EBADF path; it is now clamped.

## Fix

A `sysret()` helper per file (matching the inline pattern already there), plus
`isatty` clamped to 0/1 and `openat`'s unsupported-dirfd path setting EBADF
instead of returning a bare -1.

## Regression cover

`tools/gcc_diff_probe.sh` case `syscall-errno-convention` checks return AND
errno for ten failing syscalls against gcc, and `isatty-not-negative` checks the
0/1 contract. errno is read on its own statement in both — reading it in the
argument list of the call that sets it is unspecified order and has burned this
repo twice.

## Gate

`gcc_diff_probe` clean on native/i386/arm32/aarch64, `gate.sh lib` green,
c-testsuite 219/0/1.

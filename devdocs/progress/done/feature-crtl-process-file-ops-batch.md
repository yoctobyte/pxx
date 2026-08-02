---
track: B
prio: 25
type: feature
status: done
---

# crtl gap batch: `chdir`, `dup`, `dup2`, `symlink`, `link`

- **Type:** feature (libraries) — **Track B** (`lib/crtl`)
- **Filed:** 2026-08-02 under [[feature-crtl-implement-libc-assumptions]], from
  the round-6 probe. Ranked as its own batch, per that collector's rule.

## Measured

Present and callable already: `rmdir`, `unlink`, `ftruncate`, `fsync`, `mkdir`,
`chmod`, `fchmod`, `umask`, `rename`, `remove`. Not declared:

| symbol | header | note |
| --- | --- | --- |
| `chdir` | unistd.h | **DONE 2026-08-02** (was the last round-1 gap) |
| `dup` | unistd.h | **DONE 2026-08-02** |
| `dup2` | unistd.h | **DONE 2026-08-02** (`PalDup2` existed; bridge only) |
| `symlink` | unistd.h | **DONE 2026-08-02** |
| `link` | unistd.h | **DONE 2026-08-02** |

## Cost is uneven, which is the useful part of this note

`dup2` is nearly free: `lib/rtl/platform.pas` already exports `PalDup2`
(`platform.pas:192`), so it needs a `__pxx_dup2` bridge in `lib/rtl/pxxcio.pas`
and a declaration. `dup` is `PalDup2`-adjacent but has no PAL entry of its own.

`chdir`, `symlink` and `link` need **new PAL surface** (syscall in the posix
backend, an honest `PAL_ERR_UNSUPPORTED` in the ESP one, plus the `__pxx_`
bridge). That is the same shape as `PalConnectUnix` added on 2026-08-02 — see
that commit for the pattern, including the i386 `socketcall`-style caveat that
some syscalls take a different path on 32-bit.

So this splits cleanly: do `dup2`/`dup` first for a cheap win, and treat the
three filesystem calls as the real work.

## A caution about `chdir`

It changes process-global state, and `lib/rtl` caches nothing about the working
directory today, so nothing in-tree should go stale. Worth confirming that
`PalGetcwd`'s callers do not memoise before adding it, since a stale cwd after a
`chdir` would be a silent wrong path rather than an error.

## Gate

A differential test against gcc per call, in the style of
`test/cstring_batch.c` — whole output diffed, no recorded expectations. `dup2`
proven by redirecting a real fd and reading it back; `symlink`/`link` by
creating one in `/tmp` and `stat`-ing both ends. Cross-check
i386/aarch64/arm32, since `lib/crtl` builds for every target while `gate.sh lib`
is x86-64 only ([[frank2-crtl-changes-need-cross-check]]).

## dup / dup2 landed 2026-08-02 (commit fcc86ac39)

The cheap half, as this ticket predicted. `__pxx_dup2` bridges `PalDup2`;
`__pxx_dup` is `PalFcntl(fd, F_DUPFD, 0)`, which *is* dup()'s definition rather
than a stand-in for a missing primitive, so nothing new was needed in the PAL.

Verified behaviourally in `test/cdup.c`, not by return code: the duplicate must
actually read the same file, and `dup2` must land on the descriptor it was
given (17, chosen so a "returns some fd" implementation would fail). Identical
to gcc on x86-64, i386, aarch64 and arm32.

**Still open: `chdir`, `symlink`, `link`** — the three that need new PAL surface
in both backends. The caution about `chdir` above still applies.

## chdir / symlink / link landed 2026-08-02 (commit 0b1122ed8) — batch complete

New PAL surface in both backends: `PalChdir`, `PalSymlink`, `PalLink`, with the
ESP backend refusing them (`PAL_ERR_UNSUPPORTED`) rather than faking — a chdir
that silently did nothing would make every later relative path wrong.

`symlink`/`link` reach the kernel through **`symlinkat`/`linkat` with
`AT_FDCWD`**, not the legacy syscalls: aarch64 and riscv do not have
`symlink`/`link` at all, so the `*at` form is the only spelling that exists on
every target — the same reason `openat`/`unlinkat`/`renameat` are used
elsewhere in the backend. Note the argument shapes differ: `symlinkat` puts the
dirfd in the MIDDLE (`target, dirfd, linkpath`) while `linkat` brackets it
(`olddirfd, old, newdirfd, new, flags`).

The `chdir` caution above was checked, not assumed: nothing in `lib/rtl` or
`compiler/builtin` memoises the working directory — every caller goes straight
to `PalGetcwd` — so there is no stale cache to invalidate.

**Syscall numbers came from kernel headers on the build box** for x86-64, i386
and the asm-generic pair (aarch64/riscv). arm32 has no header here, so its
numbers were derived from the ordering the backend's existing entries pin
(openat=322 … renameat=329 … readlinkat=332), which puts linkat=330 and
symlinkat=331. **The qemu-arm run is what confirms that**, not the reasoning —
recorded in the test so a future reader knows which numbers were verified and
which were inferred-then-tested.

Verified behaviourally in `test/cfileops.c`: `chdir` must make a RELATIVE path
resolve against the new directory (not merely return 0), `lstat` must see a
link where `stat` follows it, the hard link must expose the same content, and
the failure cases must fail. Identical to gcc on x86-64, i386, aarch64, arm32.

### One assertion deliberately absent

The natural proof of a hard link is the target's `st_nlink` reaching 2. pxx
reports 1 — `lib/crtl/src/sys/stat.c` assigns it unconditionally and the PAL
never carried the field. That is not this change; filed as
[[bug-b-crtl-stat-nlink-hardcoded]], and the test proves the link by content
instead rather than asserting something known-wrong or quietly dropping the
case.

## Log
- 2026-08-02 — resolved, commit PENDING.

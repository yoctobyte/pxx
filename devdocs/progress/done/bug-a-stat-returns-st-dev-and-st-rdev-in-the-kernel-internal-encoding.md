# stat() returned st_dev/st_rdev in the kernel-internal encoding, and dev_t was 32 bits at ILP32

- **Type:** bug (Track A — `lib/rtl/platform/posix/platform_backend.pas`,
  `lib/crtl/include/sys/types.h`, `lib/crtl/include/sys/stat.h`).
- **Status:** done
- **Found:** 2026-09-01, auditing crtl for ABI defects that only bite at 32
  bits — the class frankD handed over after finding `clock_t` declared
  `long long` where glibc has `long`.
- **Closed:** 2026-09-01

## Symptom
Two independent defects in one field, neither of which errors.

**1. Wrong encoding, every target.** `DoStatx` packed `info.Dev` and
`info.Rdev` as `(major << 20) | minor` — the KERNEL-INTERNAL `MKDEV`. Userspace
`dev_t` is a different packing, the one glibc's `<sys/sysmacros.h>` implements
and the one crtl transcribes correctly. Measured on the same box, same file:

```
              glibc          pxx
/dev/null     st_rdev=0x103  st_rdev=0x100003
major:minor   1:3            0:259
```

`0:259` is a perfectly good pair. `ls -l /dev` would have printed it.

`mknod(2)` takes the USERSPACE encoding and crtl's `mknod` already passed `dev`
straight through, so before this fix `stat` and `mknod` disagreed with each
other about what a `dev_t` is.

**2. `dev_t` 32 bits at ILP32.** `typedef unsigned long dev_t` is 4 bytes on
i386/arm32/riscv32. The userspace encoding puts `(major & ~0xfff)` at bit 32,
so it truncated:

```
makedev(4096,1)   x86_64,aarch64 -> 4096:1     i386,arm32,riscv32 -> 0:1
```

glibc's `dev_t` is `__uint64_t` on every target, independent of
`_FILE_OFFSET_BITS`.

## Why nothing caught it
`test/c_sysmacros_dev.c` has the right rows — including `makedev(4096,1)` and
the 1048575 minors — and was green throughout. Every `dev_t` it inspects is one
`makedev()` just built, so it proves the three macros agree WITH EACH OTHER.
The populations it never sampled are the two the bugs lived in: a `dev_t` that
came from `stat(2)`, and any target where `long` is 32 bits. Right assertions,
wrong population — see CLAUDE.md, "a control from the wrong population passes
and certifies the broken instrument".

## Fix
`EncodeDevUser(major, minor)` in the PAL, used for both `info.Rdev` and
`info.Dev`; `dev_t` and `ino_t` widened to `unsigned long long`, `blkcnt_t` to
`long long`.

`ino_t` and `blkcnt_t` are the same one-word mistake in the same file and are
**reasoned, not observed**: the largest inode anywhere on this host is
`0xF0000000`, which fits an unsigned 32-bit field, and no file here is large
enough to overflow 32 bits of 512-byte blocks. statx hands both back as u64 and
glibc is 64-bit for both; that is the argument.

## Verified
`test/c_stat_rdev_decodes.c` — stats `/dev/null` and `/dev/zero` and asserts
1:3 and 1:5, and keeps two `makedev` round-trip rows so a "fix" that bent the
MACROS to match a wrong encoder fails here instead of passing both ways. Wired
native plus i386/arm32/riscv32 cross rows.

Positive control, observed rather than asserted: the test FAILED before each
half of the fix and on the exact population — `null 0:259` on all five targets
before the encoder change, then `makedev(4096,1) 0:1` on the three ILP32
targets before the width change.

Regression control for the struct-layout move: the runtime stat probe (size,
mode, nlink, uid, mtime, blksize) still matches the gcc oracle on x86_64, i386,
aarch64, arm32 and riscv32.

`make compiler/pascal26` → `converged after 1 round(s)`.
`tools/gate.sh quick` → `gate: GREEN (exit 0)`, FPC seed canary PASS.

## Residual, NOT fixed here
The same differential (`gcc -m32 -D_FILE_OFFSET_BITS=64` vs
`pxx --target=i386`, `_GNU_SOURCE` set explicitly) leaves three rows open:

```
           glibc-m32   pxx-i386
off_t       8           4
blkcnt_t    8           8  (fixed here)
sigset_t  128          64
```

`off_t` is NOT a one-line widening: `lib/crtl/src/fcntl.c` documents that
`struct flock` matches the kernel's native layout precisely BECAUSE
`off_t == long`, so widening it silently breaks `F_SETLK` at ILP32 unless the
same change moves to `F_SETLK64`/`struct flock64`, and `lseek`/`pread`/`pwrite`
move to `_llseek`/`pread64`/`pwrite64` with split arguments. That is a group,
and it is filed separately as
`feature-a-crtl-is-not-large-file-safe-at-ilp32`. `sigset_t` is internally
consistent and untested; it rides with that ticket.

---
slug: feature-crtl-runtime-gaps-from-e2fsprogs-util-linux-dosfstools
track: C
prio: 50
type: feature
status: done
owner: pxx2
created: 2026-11-16
closed: 2026-11-19
found-by: pixx-cc, building disk tools for pixx at 2491105c8d (repros: /data/projects/pixx/work/tooltest/repro/)
tags: [crtl]
blocked-by: []
summary: "Done: sbrk/brk, secure_getenv, off64_t/lseek64/pread64/pwrite64, struct stat64 + stat64/fstat64/lstat64/fstatat64, qsort_r, <err.h>, program_invocation_name/_short_name, _POSIX_VDISABLE, CPU_*_S + CPU_ALLOC, pthread_atfork. posix_memalign and mbstowcs/wcstombs/mbtowc were already there. The busybox_diff `_pair` suggestion moved to backlog-tools."
---

# crtl runtime gaps from e2fsprogs, util-linux and dosfstools

Reported by pixx-cc with a probe for each missing name. Fixed on 2026-11-19
in the crtl lane (pxx2). Each probe now builds and runs, and
test/c_crtl_lfs_gnu_gaps.c (rows c_lfsgnu26 and c_lfsgnu26_i386) matches gcc
on x86-64 and on i386.

## Already present when measured
posix_memalign, mbstowcs, wcstombs and mbtowc.

## Added
- **`<err.h>`**: warn/warnx/err/errx and their v-forms. They print glibc's
  format byte for byte and save errno before anything else is printed.
  Without this header, `#include <err.h>` fell through to the host's glibc
  copy, which pxx cannot parse.
- **program_invocation_name and program_invocation_short_name** (unistd.c):
  set from argv[0] in `__pxx_run_initializers`. `CNeedsEnvironInit`
  (cparser.inc) now also fires on these two names. err.c falls back to
  /proc/self/comm when they are NULL, as in a shared library.
- **LFS64**:
  - `off64_t`, `ino64_t` and `blkcnt64_t` are 64-bit on every target.
  - `lseek64` is the PAL seek, which was already 64-bit.
  - `pread64` and `pwrite64` are pread/pwrite on LP64. On ILP32 they use a
    seek-based form with the full offset.
  - `struct stat64` is struct stat with a 64-bit st_size. On ILP32 Linux,
    stat64/fstat64/lstat64/fstatat64 read statx directly. Elsewhere they
    widen what stat returns.
  - `open64` adds O_LARGEFILE on ILP32.
- **PalBackendSeek on i386 and arm32** now uses `_llseek` (140). Plain lseek
  carries a 32-bit offset on those ABIs, so a seek past 2 GiB failed. That
  showed up as soon as lseek64 existed. A Pascal Seek/FileSize round trip was
  checked on x86_64, i386 and arm32.
- **brk/sbrk**: raw SYS_brk, or ENOSYS where the target has none. pxx's heap
  is mmap-backed, so nothing else moves the break.
- **secure_getenv**: returns NULL when the real and effective uid or gid
  differ.
- **qsort_r**: GNU argument order, same insertion sort as qsort. qsort's O(n²)
  is a separate matter.
- **_POSIX_VDISABLE**: `'\0'`, in termios.h and in unistd.h.
- **CPU_SET_S, CPU_CLR_S, CPU_ISSET_S, CPU_ALLOC, CPU_FREE, CPU_ALLOC_SIZE**:
  glibc's shape. A cpu outside setsize is ignored.
- **pthread_atfork**: up to 32 handler triples. fork() runs them through
  `__crtl_atfork_hook`: prepare in reverse order, then parent or child in
  registration order.

## Also fixed
test/crtl_lfs64_aliases_b234.c passed a `struct stat` to stat64. It now uses
struct stat64.

## Moved out
The busybox_diff.sh `_pair` entries (fdisk FEATURE_FDISK_WRITABLE,
FEATURE_GPT_LABEL, FEATURE_FDISK_ADVANCED, FDISK_SUPPORT_LARGE_DISKS;
mkdosfs MKFS_VFAT) need a busybox build to prove them. They are now
devdocs/progress/backlog-tools/feature-t-busybox-diff-fdisk-mkdosfs-options.md.

---
summary: "crtl: sync_file_range(2) and its SYNC_FILE_RANGE_* flags in <fcntl.h> (git's wrapper.c)"
type: feature
prio: 40
---

# crtl: sync_file_range

- **Type:** feature (crtl). Needed 2026-11-28 by the Nodisx git recipe: git's
  config.mak.uname sets HAVE_SYNC_FILE_RANGE for Linux, and wrapper.c then
  calls sync_file_range with SYNC_FILE_RANGE_WAIT_BEFORE and the others.
- **Status:** done

## What landed

- <fcntl.h> has the four flags (the kernel's values: 1, 2, 4, and 7 for
  WRITE_AND_WAIT) and `int sync_file_range(int, off64_t, off64_t, unsigned)`,
  as glibc declares them.
- src/fcntl.c has one syscall shape per ABI, as posix_fadvise does:
  - x86-64, aarch64 and riscv64 take (fd, off, n, flags);
  - i386 passes each 64-bit value as a lo/hi pair;
  - arm32 uses sync_file_range2, with flags second;
  - riscv32, wasm and xtensa get ENOSYS.
- Failures return -1 with errno set, as glibc.

Test c_crtl_sync_file_range (row c_sfr26), against glibc on x86-64 and i386.
It checks every flag, an offset past 4 GiB, a negative offset (EINVAL, which
needs the i386 high word to be passed), bad flags and a bad fd.

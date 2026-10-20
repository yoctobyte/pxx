---
track: N
prio: 20
type: feature
---

# os.stat st_uid/st_gid/st_ino/st_nlink/st_mtime, os.getpid/getuid/getgid

Asked 2026-10-20 by neo-73: Vloot's faster process scan reads a process's
owner as `os.stat("/proc/<pid>").st_uid`. Natively that raised
`AttributeError: 'TPyStat' object has no attribute 'st_uid'`. TPyStat had only
st_mode and st_size, and os.getpid/getuid/geteuid/getgid and
os.path.getmtime didn't exist.

**Fix:**
- pypal `PyPalStatFull` reads the same one syscall as before (x86-64 `stat`,
  statx elsewhere) and returns mode, size, uid, gid, ino, nlink and mtime in
  nanoseconds. PyPalStatModeSize now wraps it.
- TPyStat gains `st_uid`, `st_gid`, `st_ino`, `st_nlink`, `st_mtime` and
  `st_mtime_ns`.
- `PyPalGetId` with getpid/getuid/geteuid/getgid numbers per target. i386 and
  arm32 use the 32-bit-id syscalls. ESP and wasm32 return 0.
- `os.getpid`, `os.getuid`, `os.geteuid`, `os.getgid` and `os.path.getmtime`
  are mapped in PyStdlibCallProc.

Checked against python3 on x86-64, and on aarch64, i386, arm32 and riscv32
under qemu. Test: `test_nilpy_os_stat_owner_and_ids` (relations, since values
differ per machine; x86-64 and aarch64).

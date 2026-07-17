---
prio: 70
---

# regression: test-c-conformance-riscv32#shard0/6 red at ba5b85d6122d (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-15T07:23:10Z
- **Test source:** tools/run_c_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-c-conformance-riscv32#shard0/6'` at ba5b85d6122d674c1b76890b52135618f70ea630

## Range
bad `ba5b85d6122d`, last good `ba5b85d6122d`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL 00187.c — output mismatch:
    --- library_candidates/c-testsuite/tests/single-exec/00187.c.expected	2026-07-07 21:11:07.000000000 +0200
    +++ /tmp/pxx_c_conformance.713527/out.txt	2026-07-15 09:20:06.728716445 +0200
    @@ -11,17 +11,3 @@
     ch: 108 'l'
     ch: 111 'o'
     ch: 10 '.'
    -ch: 104 'h'
    -ch: 101 'e'
test-c-conformance-riscv32: 36 pass, 1 fail, 0 skip (of 37)
test-c-conformance-riscv32: FAILURES: 00187.c(output)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triage (2026-07-17, T face-2 enrich)

**Real riscv32-specific libc-free stdio/file-VFS bug — not a flake.** `00187.c` does
file I/O: `fwrite("hello\nhello\n", 1, 12, f)` (12 bytes) then reads it back via
`fread`, `fgetc`, `getc`, `fgets` loops. Output **truncates at exactly 6 of 12 bytes**:
the first `fgetc` loop stops after the first `hello\n` (`ch: 10 '.'`) and never reaches
the second `hello` (`ch: 104 'h'` onward). Deterministic (36 pass / 1 fail, output
mismatch — not timing).

- **Locus:** the riscv32 **file-VFS / stdio PAL bridge** in the libc-free `crtl` file
  path (see [[project_c_stdio_pal_bridge_done]], [[project_sqlite_file_vfs_wall4_null_syscall_slot]],
  [[project_c_sqlite_file_vfs_...]]). The 6-of-12 split points at a **short `fwrite`**
  (only half the buffer hit disk) or a **file-position/`fread` interaction** leaving the
  stream at offset 6 so the first `fgetc` loop sees premature EOF.
- **Owning lane:** riscv32 cross runtime → **Track A** (backend/PAL/crtl file path), or
  Track C if the defect is in C-specific stdio lowering. T owns the tool, not the bug —
  filed here for a dev track to take.
- **Next step to localize:** on qemu-riscv32, run a 2-line repro — `fwrite` N bytes,
  reopen, `ftell`/`fread` — and check the byte count actually written vs the offset seen
  on read. Compare against x86-64 (passes) to confirm it's the riscv32 file syscall
  slot / buffering, not the C logic.
- **Age:** found 2026-07-15 (`ba5b85d6`), pre-dates the current session; 0-in-range
  (watcher couldn't bisect a single-commit window).

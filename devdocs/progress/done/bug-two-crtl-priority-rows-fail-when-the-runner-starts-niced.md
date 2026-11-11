---
track: C
prio: 40
type: bug
blocked-by: []
summary: "c_crtl_mount_and_prio row 3 and c_crtl_busybox_394_gaps row 9 went red whenever the test runner itself ran niced (the fleet runs every heavy command under `nice -n 15`). Both raise the niceness and expect the full step, and niceness stops at 19. Not a compiler or crtl bug: the binaries from the master compiler and from gcc behaved the same. The rows now expect the clamped step."
status: done
owner: unassigned
---

# Two crtl priority rows fail when the runner starts niced

## Found

The 2026-11-11 full tiers, both run under `nice -n 15`, failed test-core
c_crtl_mount_and_prio (`3 0 0` for `3 3 0`) and c_crtl_busybox_394_gaps
(`9 1 0` for `9 1 1`). Run by hand at nice 0 they passed. At `nice -n 19` the
master compiler's binaries failed the same way, so this was the environment,
not the code under test.

## Cause

Row 3 calls setpriority(base + 3) and expects to read back base + 3. Row 9
calls nice(1) and expects base + 1. Niceness is capped at 19. A process that
starts at 17 or above cannot rise by 3, and one at 19 cannot rise at all, so
the kernel clamps and the rows read the clamp as a failure.

## Fix

Both rows now expect the clamped step: `min(3, 19 - base)` for row 3 and
`min(base + 1, 19)` for row 9. The printed output is unchanged (`3 3 0`,
`9 1 1`), so the Makefile expectations and the gcc-parity reading still hold.

Row 3 still catches the bug it was written for, a wrapper that forwards the
kernel's raw `20 - nice`. Such a wrapper reads a small base and then asks to
LOWER the niceness, which setpriority refuses without privilege, so the row
prints `setpriority-failed`.

## Checked

- Both recipe lines from the Makefile pass at nice 0, 15 and 19.
- c_crtl_mount_and_prio: pxx and gcc give identical output at all three
  levels.

---
track: T
tags: [test-core, freebsd, syscalls, tooling]
prio: 20
type: bug
blocked-by: []
summary: "`make test-core` stops at its 9th row: freebsd_kernel_entries expects `2 kernel-entry` in `--os=freebsd test/test_rtl_libc_torture.pas` and gets 5. Every compiler checked gives 5, back to the v455 freeze master-a7c7ff69b7 (2026-10-31), so the row has been red for weeks. Every test-core row after it (including the xtensa object checks added 2026-11-17) has not run in `make test-core` since then. Either three sites now bypass the FreeBSD syscall thunk (a real bug: they would issue LINUX numbers on FreeBSD) or the expectation is stale; tools/syscall_scan.py on the binary says where."
status: backlog
owner: unassigned
---

# test-core stops at freebsd_kernel_entries (5, not 2)

Found 2026-11-17 while running test-core for the xtensa PAL change. Measured with the current tree, all of 11-17's published builds, ~/pxx (5d0a7059c2) and ~/pxx-frozen/master-a7c7ff69b7: all give 5.

Next step: `python3 tools/syscall_scan.py <fb binary>` to list the five entries. A site outside the translator thunk and rt_sigreturn is a real FreeBSD bug.

Meanwhile, rows after it in test-core must be run on their own. The 2026-11-17 xtensa rows (tools/check_xtensa_*.py, c_busybox_hush_gaps) were.

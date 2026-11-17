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

## Rows it was hiding (found 2026-11-17, running test-core from a copy with these rows disabled)
- freebsd_c_kernel_entries (the C twin, two lines down) also gives 5, not 2.
- casm_nonempty_template_fails still asserted that `"+r"` is refused, but `"+r"` was supported by the dropbear commit b1b534c3c6. GRADUATED in the inline-asm commit of 2026-11-17: it now asserts that the file compiles and prints 0.
- csyncat_a64_order (aarch64 `__sync` compare-exchange byte sequence) counts 4, the row wants 3. The latest build and the v455 freeze both give 4. Either a fourth site now uses the sequence (likely, and harmless) or the count drifted; whoever touches aarch64 atomics should decide which. Not fixed.
Rows after these may hide more. Until the freebsd row is fixed, a test-core run means a copy of the Makefile with the known rows set to `true`.
- catomic_spec still expects `_Atomic(int)` to be refused, but 5239196c40 supports it. Stale; not fixed yet.
- casmmpress26 (test/casm_m_operand_pressure.c, nine "m" operands through *v): "needs more registers than this frontend can pin". latest-35a7977144 does the same. A dereferenced "m" now takes a pool register (bug-c-an-m-operand-that-is-a-dereference-binds-a-copy), so nine of them exceed the pool of 9. Real regression, not stale. Not fixed.
- A full `make -i test-core` on 2026-11-17 also showed red: c_crtl_enosys26; the cstatic_distinct*, cstaticext26* and cstatic_vars26 rows; c_wasm32_hosted_stdio and c_wasm32_math_h; c_block_scope_extern; c_va_arg_every_target and c_int_signedness_every_target (wasm32); and c_incomplete_type_member_refused. Whether each is stale or a regression is still to be decided (a baseline run with latest is in progress).

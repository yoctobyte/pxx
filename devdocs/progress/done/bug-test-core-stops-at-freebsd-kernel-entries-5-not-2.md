---
track: T
tags: [test-core, freebsd, syscalls, tooling]
prio: 20
type: bug
blocked-by: []
summary: "DONE 2026-11-19 (rd). The five FreeBSD kernel entries are all legitimate: FbRawA (the translator's own), the never-reached rt_sigreturn in the entry stub, and FbClearTidExit's three (_umtx_op wake twice, thr_exit; registers only because the joiner may unmap the stack once the tid word clears, fbsdabi.pas, 2026-11-12). Both rows now expect 5 and say so; a sixth still fails. A full `make -i test-core` then showed 28 failures; eleven stale rows are graduated (below), and the cstatic family was a test vehicle broken by b3c5f711ea, now fixed. Four reds remain, each a real gap: bug-test-core-four-rows-still-red-2026-11-19."
status: done
owner: rd
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

## Resolution (2026-11-19, rd)

`tools/syscall_scan.py BIN --list` plus `--proc-map` attributed the five sites
(Pascal and the C twin alike): entry stub (rt_sigreturn), FbRawA, and three in
FbClearTidExit. All by design; both rows say 5 and list them.

`make -i test-core` on b2cd388a0c then gave 28 failures. Each was classified
by measuring a frozen build and, where it moved, the commit:

Stale rows, graduated (each now asserts the new behaviour):
- c_fsalias26_refuse: file-scope asm code is assembled since 8d21004d32; now
  checks `T myfunc` / `W alias2` (row c_fsalias26_code).
- cfsi_fs: --freestanding refuses SSE since 28c9b6aa10, and printf of a double
  needs it (gcc -mgeneral-regs-only too). -DNO_SSE hands the baked float/double
  to a gcc-built helper (test/fixtures/cfsi_show_fp.c); expected unchanged.
- link-freestanding VLA control: VLAs compile under --freestanding since
  28c9b6aa10; the control now asserts that.
- c_attribute_mode_ti_is_refused: __int128 since 9620c9a69b; x86-64 compiles
  mode(TI), the refusal row moved to --target=i386.
- c_block_scope_extern (bsx_unk): refused now as gcc's link does
  ("undefined reference to extern variable"); either refusal accepted.
- catomic_spec: _Atomic(int) works (5239196c40); runs, "7 4" as gcc.
- csyncat_a64_order: 4 sites, the fourth is __pxx_a_fence (a cas32 on a
  local), by design.
- test_ir_deref: used the compiler-internal TFixup that no longer leaks into
  programs; declares its own record.
- c_crtl_enosys26: chroot (54c5b98b5f) and set*id are real syscalls; a gcc
  differential now (EPERM unprivileged), the ENOSYS contract kept under
  -DENOSYS_CONTRACT.
- c_incomplete_type_member_refused: the opaque arm became a warning plus gcc's
  biggest alignment in b3c5f711ea; counts the warning. i386 layout gap filed:
  bug-c-aligned-alignof-long-double-on-i386.
- fxpal xtensa longsec: xtensa uses futex_time64 since c6e9247e2c, so it is in
  the 64-bit group (must not return), like riscv32.

The cstatic family (cstaticext26/26b/.o, cstatic_distinct*, cstatic_vars26):
bisected to b3c5f711ea (good 5717b8b428). That commit made an #included USER
.c part of the includer's TU (correct C; busybox bzip2 needed it) and only
lib/crtl/ paths modules. The fixtures stood in for crtl modules, so they moved
to test/fixtures/as_crtl/lib/crtl/ (cstatic_ext_pub.c stays a user file, as
libtomcrypt is in dropbear). All rows pass and match gcc's -DSEPARATE_TU build.
The real dropbear shape (crtl crypt.c's static sha512_init vs a user external
one) was re-checked: pxx and gcc both print "42 1005 7 1".

Still red: bug-test-core-four-rows-still-red-2026-11-19.

# Cross external-C-call ABI breadth (float/Int64 args, float returns, stack align)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-17 (follow-up from feature-cross-target-feature-parity item 3)
- **Depends-on:** feature-cross-target-feature-parity (external C calls v1 — done all 4 targets)

## Motivation

External C calls landed on all four hosted targets (i386 cdecl, aarch64 AAPCS,
arm32 AAPCS32) with a deliberately narrow **v1 ABI**: 4/8-byte scalar/pointer
arguments and an integer/pointer return only. Anything else is a hard
`Error('… not yet supported')`. That covers the SQLite/header C-import surface
(all int/pointer), but blocks any C API that passes or returns floating-point or
64-bit values — e.g. `libm` (`sin`/`pow` → double), `sqlite3_bind_double`,
`sqlite3_column_int64`, time/size APIs returning 64-bit on 32-bit targets.

x86-64 already has the full ABI (SysV class assignment, xmm0..7, edx:eax/rax,
float return bridged from xmm0); this ticket brings the three cross targets up to
the same coverage and removes the v1 alignment shortcut.

## Scope

Per target, for **external** (`cdecl`/AAPCS) calls only — the internal Pascal
convention is unaffected:

1. **Float arguments + returns.**
   - i386: floats on the stack (cdecl passes all args on the stack; a `double`
     is 8 bytes, a `single` 4); float **return** comes back in `st0` → load to
     the value model. Today both error.
   - aarch64: AAPCS uses `v0..v7` for FP args, `v0` for the FP return; integer
     and FP arg registers are counted independently (mirror the x86-64 SysV
     two-class split already implemented).
   - arm32: base AAPCS (no VFP arg regs in the soft-float variant we emit) passes
     FP args in core registers / on the stack; a `double` is two words. Decide
     and document hard-float (VFP `d0`) vs soft-float once a real `libm` call is
     wired — the emitted ELF flags (`EF_ARM`) must match the chosen loader
     (armel `/lib/ld-linux.so.3` vs armhf `/lib/ld-linux-armhf.so.3`).

2. **Int64 / UInt64 arguments + returns.**
   - i386: pass as two stack words (lo then hi); return in `edx:eax` (the
     internal 64-bit model already uses this pair).
   - arm32: pass as a register/stack pair (AAPCS r0:r1 alignment rule — 64-bit
     args start on an even register); return in `r0:r1`.
   - aarch64: native 64-bit, already fine for the value but verify the external
     path doesn't reject it.

3. **i386 stack 16-alignment.** v1 skips it (correct cdecl arg layout + caller
   cleanup, but `esp` is not 16-aligned at the `call`). Modern glibc/SSE callees
   may fault. Add the realign-around-call dance (save `esp`, `and esp,-16`,
   reserve the arg block, restore after) like the x86-64 external path. aarch64
   (`sp` 16-aligned by construction) and arm32 (8-byte) need a check, not new
   code.

## Validation

Extend `test_extern_c` (or a new `test_extern_c_float`/`_int64`) to call libc/libm
functions exercising each case — e.g. `strtod`/`atof` (double return), `pow`/`sin`
(double args+return, needs `-lm` → DT_NEEDED `libm.so.6`), `atoll` (Int64 return),
`llabs` (Int64 arg+return). Run on all four targets; output must equal the x86-64
build (behavioural parity — this is a feature test, not a self-host byte gate).
The aarch64/arm32 guest `libm.so.6` is already in the cross sysroots provisioned
by `tools/install_cross_sysroot.sh`.

## Acceptance

External C calls accept float/single/double and Int64/UInt64 arguments and return
values on i386/aarch64/arm32 with output identical to x86-64; the i386 external
call site is 16-byte aligned; the v1 hard-errors are removed; `make test` +
the three cross suites + `make cross-bootstrap` stay green.

## Log
- 2026-06-17 — opened as the v1 follow-up. External-call v1 (int/pointer only)
  shipped on all four targets in feature-cross-target-feature-parity (commits
  39681b8 i386, c70001f aarch64+arm32). The three hard-error guards to lift live
  at ir_codegen386.inc / ir_codegen_aarch64.inc / ir_codegen_arm32.inc (the
  `external call float/Int64 … not yet supported` paths).

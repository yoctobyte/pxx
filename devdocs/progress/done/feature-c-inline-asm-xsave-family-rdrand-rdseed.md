---
track: C
tags: [c, asm, x86-64, gibux]
prio: 60
type: feature
blocked-by: []
summary: "x86-64 C inline asm encodes the XSAVE family (xsave/xrstor/xsaveopt/xsavec, with and without 64), xsetbv, rdrand and rdseed, and set<cc> in AT&T templates. The \"=qm\" constraint is read as \"=q\". All of these were refused as unsupported, which stopped Gibux's XSAVE/AVX and entropy work."
status: done
owner: claude
---

# C inline asm: the XSAVE family, xsetbv, rdrand/rdseed

Gibux turned on XSAVE/AVX state (CR4.OSXSAVE, XCR0, per-process xsave areas,
Linux xstate signal frames) and a hardware entropy source. pascal26 refused
each instruction with `inline asm template has an unsupported instruction`.

Encodings, in AsmSystemOp (asmenc.inc):
- xsave /4, xrstor /5, xsaveopt /6: 0F AE with a memory operand;
- xsavec /4: 0F C7 with a memory operand;
- the `64` spellings add REX.W.
- xsetbv: 0F 01 D1. It is also in the Intel-syntax encoder and the GAS
  frontend, next to xgetbv.
- rdrand /6, rdseed /7: 0F C7 with a register operand (mod=11). A 16-bit
  register adds 66, a 64-bit one adds REX.W, r8..r15 add REX.B.

In the AT&T parser:
- `set<cc>` is now a known base, so `rdrand %0; setc %1` assembles. The
  shared encoder already had setcc; only the parser's base list lacked it.
- `"qm"` / `"Qm"` constraints read as `q` / `Q`. A byte register is always
  one of the choices they allow, the same reading that turns `rm` into a
  register.

Test: test/casm_kernel_system_instructions.c gained 17 rows and
tools/casm_sysinsn_vs_gcc.sh's picker gained the new mnemonics. pxx and gcc
now agree byte for byte on 56 system instructions, including SIB (r12) and
disp8 (r13) memory forms.

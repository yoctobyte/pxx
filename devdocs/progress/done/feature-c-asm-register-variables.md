---
slug: feature-c-asm-register-variables
track: C
prio: 30
type: feature
status: done
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [c-frontend, inline-asm, toybox]
blocked-by: []
summary: "`register long x __asm__(\"r9\")` local register variables are unsupported; seen in syscall wrappers."
---

# C: explicit register variables

Not needed by toybox defconfig; noted while porting.

## Done 2026-11-19 (rd, the Rainyday kernel seat)

Found blocking Rainyday's own tests/xtensa programs, which reach the kernel
through `register long a2 __asm__("a2") = n;` and friends. pxx refused them
with "expected C expression".

- **Front end.** A local declarator followed by `asm("reg")` (or `__asm`,
  `__asm__`) records a binding: CRegVarAdd, keyed by name and the SymCount at
  the declaration. The variable is otherwise an ordinary local. gcc
  guarantees the binding only at an inline-asm operand, and that is the only
  place pxx honours it.
- **Operands.** A register-class operand (`r`, `g`, `rm`, `mr`) that is
  exactly such a variable gets TCAsmOperand.FixReg (CRegVarOf).
- **x86-64 and i386.** The builder takes FixReg through AsmRegNum as a fixed
  register. That covers r8..r15 as well, which no constraint letter can
  name.
- **xtensa.**
  - Bound operands are pinned before the pool is filled.
  - Inputs are loaded straight into their register by EmitLoadVarOwnXtensa,
    which addresses through the destination itself. a2, a8 and a9 are
    therefore free to bind, which a six-argument syscall needs (a8 and a9).
  - Outputs are stored back through a2, with the a2-bound output first. An
    output bound to a8 or a9 is refused by name.
- **Other targets.** A bound operand is refused by name.
- **i386 `int $imm8`.** Was missing from the inline assembler, which stopped
  the i386 syscall shape. CD ib, as gas emits it.

Measured:
- test/c_asm_register_variables.c matches gcc on x86-64 and i386 (-m32) and
  runs on hosted xtensa call0 (test-core and test-xtensa rows).
- Rainyday's tests/xtensa/abi32.c, mmap.c, alloca.c, vfork.c and romfile.c
  were built with pxx (--emit-obj, linked with prog-fixed.ld) and booted as
  init on the Rainyday S3 kernel in QEMU. All print ok, as the gcc builds do.

fixed.c, selfexe.c and signal.c still stop on file-scope asm that defines
code (`.text` ...). That is the rump ticket's S3 gap: it needs an assembler
pass for file-scope asm. It is not this one.

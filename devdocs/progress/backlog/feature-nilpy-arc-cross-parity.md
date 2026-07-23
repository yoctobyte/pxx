---
track: A
prio: 35
type: feature
---

# NilPy object-ARC cross-target parity (aarch64 inline arms + scope-exit)

x86-64 has the full object-ARC surface. The cross gaps are leak-only
(retains and releases stay paired per path), not corruption:

- aarch64 EmitVariantClearA64 / EmitVariantRetainA64 (inline store arms)
  lack the VT_OBJECT/VT_BOUNDMETHOD/VT_PYCLOSURE (7/8/9) arms. Needs an
  aarch64 equivalent of the x86 ObjRetain/ReleaseBlob (all-caller-regs
  preserving wrapper over the Pascal procs) or rerouting those emitters
  to the portable PXXVarClear/Retain.
- The scope-exit tyClass release arm in EmitManagedLocalCleanup exists
  only in the x86-64 branch; the arm32/aarch64/i386/rv32/xtensa cleanup
  emitters need the same (mirror their tyAnsiString arm: load slot,
  call PXXObjRelease).
- arm32/i386 inline variant stores go through the portable helpers and
  are already covered; rv32/xtensa have no NilPy story yet.

Gate: test-nilpy cross (qemu) + self-host byte-identical + cross
bootstrap unchanged. All Pascal-mode emission must stay byte-identical —
every arm is NilPy-gated or magic-guarded.

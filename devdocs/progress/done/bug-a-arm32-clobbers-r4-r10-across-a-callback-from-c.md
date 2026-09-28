---
track: A
prio: 70
type: bug
status: done
found: 2026-09-28
found-by: frankD
owner:
summary: "CRASH, arm32. A Pascal routine called BACK from C (a qsort comparator) returned with AAPCS's callee-saved r4-r10 destroyed: the arm32 prologue was `push {fp, lr}; mov fp, sp` and the body writes r9 (the frame-size literal), r4-r6 (copy helpers) freely. qsort over 2 elements (one callback) sorted; over 3 or more it SEGFAULTED inside libc. test_procaddr crashed on arm32 while green on x86-64/i386/aarch64. v446 the same. The i386 twin (ebx/esi/edi) was bug-a-i386-clobbers-ebx-across-a-cdecl-exported-function."
---

# arm32 clobbers r4-r10 across a callback from C

Found by the Pascal cross-target differential: test_procaddr segfaulted on
arm32 only. Reduced by element count: 2 elements right, 3 a segfault -- the
second callback is the first one whose caller relies on its callee-saved
registers surviving.

## Resolution (2026-09-28)

EmitProcProlog's arm32 arm spills r4-r10 into a 28-byte slot reserved below
the routine's current locals, exactly the i386 shape, and EmitProcEpilog
reloads them on every return path before `mov sp, fp`. The save area is
addressed through lr (already pushed, so free) with a literal offset, since
the frame can exceed an ARM immediate. The per-routine offset rides the same
LIFO the i386 spill uses (prologue emission nests), popped in
PatchProcPrologue.

test_procaddr now runs cross in test-core (i386/aarch64/arm32; riscv32 emits
no dynamic segment and refuses the libc external loudly).

Not measured here: riscv32's s0-s11 across a callback from C. There is no
libc on the hosted riscv32 image, so it is unreachable on this box; it matters
for ESP-IDF callbacks on the C3 and was not looked at on hardware.

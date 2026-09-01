---
track: A
prio: 45
type: bug
found: 2026-09-01
found-by: frankC
summary: "aarch64 is the last target where a by-value aggregate argument occupies one pointer-sized slot by CONSTRUCTION rather than by classification: ABIA64CdeclArgSlot advances the NSAA by a fixed 8 bytes per argument, so an aggregate of any size gets exactly one slot and its three readers inherit that. x86-64 and i386 were converted by bug-a-c-a-by-value-struct-parameter-is-passed-as-a-pointer-to-every-c-abi-callee; this is the same defect, in the one place with NO ORACLE. There is no gcc cross for aarch64 on this box, so no mixed link is constructible and the only available verification is pxx-against-pxx -- which is exactly the self-consistency the parent ticket exists to show is worthless for a calling convention. So the FIRST deliverable here is an oracle, not a fix."
---

# An aggregate argument is a pointer by construction on aarch64

`ABIA64CdeclArgSlot` (`compiler/abi.inc:521`) advances the next-stacked-argument
address by a fixed 8 per argument. AAPCS64 wants an aggregate <= 16 bytes in
one or two consecutive X registers, an aggregate of 1-4 identical float members
(an HFA) in that many V registers, and anything larger passed by reference to a
caller-made copy — the *caller* copies, and that indirection is part of the ABI
rather than a shortcut.

Readers, all inheriting the one-slot assumption:

| file | line | arm |
| --- | --- | --- |
| `ir_codegen.inc` | 1538 | callee spill |
| `ir_codegen_aarch64.inc` | 3443, 3454 | direct call |
| `ir_codegen_aarch64.inc` | 3630, 3641 | indirect call |

That is the same three-arm shape x86-64 and i386 had, and the same trap: fixing
the direct arm and not the indirect one produces a gate that passes because the
subject contains no call through a function pointer.

## THE FIRST DELIVERABLE IS AN ORACLE

**Do not start with the classifier.** The parent ticket's entire finding is that
a calling convention cannot be judged from inside one implementation: pxx agreed
with itself about passing a struct as a pointer for as long as the code existed,
and every test passed. On x86-64 and i386 the disagreement became visible only
when a gcc-compiled `main` was linked against a pxx-compiled object and the
fields were read across the boundary.

**No such link is constructible here.** Measured 2026-09-01: no
`aarch64-linux-gnu-gcc`, and the same for arm32 and riscv32. Options, cheapest
first:

1. **A cross toolchain.** `gcc-aarch64-linux-gnu` + `qemu-aarch64`, both already
   depended on elsewhere in this tree for the cross test rungs. Installing is
   the owner's call (it leaves this machine). This is the one that makes the
   fix ordinary work.
2. **A hand-written assembly caller**, assembled by pxx's own aarch64 backend
   from the AAPCS64 document. It tests the reading of the document, not
   agreement with the platform — genuinely weaker, but not worthless, and it is
   what `test-c-abi-glibc-oracle` does in spirit.
3. **A glibc entry point taking a struct by value**, under qemu. The parent
   ticket already looked: the routines this corpus calls take scalars and
   varargs, so the substitute oracle does not extend.

## Why it is not urgent

Nothing reaches it today. aarch64 has no stack argument passing for the three
C-ABI call kinds at all
([[bug-a-aarch64-has-no-stack-argument-passing-for-the-three-c-abi-call-kinds]]),
so a program that would expose the NSAA advance mostly fails earlier and more
loudly. **That is a reason to sequence the two, not a reason to defer both** —
and it is worth noticing that the louder bug is protecting the quieter one from
being observed.

Split out of [[bug-a-c-a-by-value-struct-parameter-is-passed-as-a-pointer-to-every-c-abi-callee]]
when that closed for x86-64 and i386.

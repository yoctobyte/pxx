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
# 2026-09-03 — WHAT THE MISSING ORACLE ACTUALLY NEEDS, measured

This ticket and `bug-a-an-aggregate-argument-is-a-pointer-by-construction-on-aarch64`
both say the first deliverable is an oracle and neither says what is missing.
Measured on plexus so the next reader does not re-derive it. A mixed link needs
three pieces; **two of them are already here.**

| piece | aarch64 / arm32 / riscv32 | how checked |
| --- | --- | --- |
| a foreign C compiler that emits an object | **PRESENT** — clang 21.1.8 | `clang --target=aarch64-linux-gnu -c` produces `ELF 64-bit LSB relocatable, ARM aarch64` with **no sysroot and no headers**, which is all an ABI probe needs |
| a runner | **PRESENT** — `qemu-aarch64`, `qemu-arm`, and the rest under `/usr/bin/qemu-*` | `tools/run_target.sh` already uses them |
| a LINKER for those architectures | **ABSENT** | `ld -V` lists only `elf_x86_64 elf_i386 elf32_x86_64 elf_iamcu i386pep i386pe`; no `ld.lld`, no `*-linux-gnu-gcc` of any flavour |

**So the blocker is one tool, not a toolchain.** That is worth stating precisely
because "we need a cross toolchain" reads as an expensive ask and is the reason
this has sat: the compiler and the runner are installed, and what is missing is
the thing in the middle.

Two routes neither of which works today, both checked rather than assumed:

- **pxx links it.** pxx writes aarch64 executables already, so it has the ELF
  writer. It cannot consume a foreign object: `pascal26 foo.o out` answers
  `error: unexpected character` — object files are not an accepted input, and
  `--emit-obj` itself lists **"general objects: x86-64, i386, xtensa, riscv32"**,
  so aarch64 and arm32 cannot even be emitted (that is
  `feature-a-object-output-for-arm32-and-aarch64`, p45, and it is a genuine
  second blocker for the pxx-emits/foreign-links direction — but NOT for the
  clang-emits/something-links direction, which needs only the linker).
- **GNU ld with an emulation flag.** `ld -m aarch64linux` is rejected; this
  binutils is not the multiarch build.

**What I did NOT verify, stated as the unmeasured half:** that `lld` (or
`binutils-multiarch`) would in fact close it. It is the obvious candidate and I
could not test it because it is not installed, and installing it is an apt
operation — the owner's, not an agent's. Everything above IS measured.

So the actionable form of "this needs an oracle first" is: **ask the owner for a
linker that targets aarch64/arm32/riscv32, and the rest of the rig is buildable
from parts already on the box.** `test-c-abi-mixed-link` is already written to
skip a target it cannot build and to go RED if every target skips, so extending
its target list costs nothing until the linker exists.
**CORRECTION, same day, to the note above.** It concludes that the missing piece
is a LINKER. That is true of a static mixed LINK and it is not the answer to "is
there an oracle", because **a mixed CALL is enough and it already works**:
`~/.cache/pxx-cross/{aarch64,arm32}/lib/` holds a complete glibc that
`run_target.sh` already puts on `QEMU_LD_PREFIX`, pxx already emits dynamic
imports for those targets, and a pxx caller into gcc-built glibc is a real ABI
boundary with the callee's own output as the observable. Worked instance, found
that way within the hour:
`bug-a-aarch64-passes-a-variadic-float-in-an-fp-register-so-glibc-reads-zero`
— `[0.00]` against arm32's and x86-64's `[3.50]`, where the pxx-vs-pxx version of
the same program is self-consistently wrong. Read that ticket's ORACLE section
before concluding this one is blocked. The linker is still needed for the other
direction (a pxx-compiled CALLEE receiving from gcc-compiled code), and riscv32
and xtensa are covered by neither — both refuse dynamic symbols outright.

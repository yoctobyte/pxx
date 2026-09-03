---
slug: bug-a-c-the-variadic-struct-abi-is-still-a-pointer-on-aarch64-arm32-and-riscv32
title: "A struct through `...` is still a POINTER on aarch64, arm32 and riscv32"
track: A
prio: 40
type: bug
status: backlog
created: 2026-09-02
found-by: frankA
owner: ""
blocked-by: []
summary: "The remaining three targets of bug-a-c-a-struct-through-the-variadic-tail-is-passed-as-a-pointer, which was fixed on x86-64 and i386 2026-09-02. A struct or union in a variadic slot still occupies one pointer-width slot holding the address of a caller temp; gcc puts the aggregate's own bytes there. Self-consistent inside pxx, so no pxx-vs-pxx test can see it, and there is no MIXED-LINK oracle on these three -- test-c-abi-mixed-link runs x86_64 and i386 only -- which is why they were not converted blind alongside the other two. Measured unchanged rather than regressed: arm32 and riscv32 print byte-identical output before and after that fix, aarch64 differs only in the garbage stack addresses the broken rows were already printing. The mechanism and all three sites are documented on the parent; what this needs first is an oracle."
---

# The variadic struct ABI on the three cross targets

The parent —
[[bug-a-c-a-struct-through-the-variadic-tail-is-passed-as-a-pointer]] — has the
full mechanism, the three sites and the fix that landed for x86-64 and i386.
This ticket is only what was deliberately left.

## What is already done and carries over

- **`IRLowerCallArg` stamps the record identity** on the argument's value node
  (`IRArgRecId`, `compiler/ir.inc`). That is target-independent and is already
  in place: these three backends can read it today.
- **The receiving half is per-target.** x86-64 materialises a temp and calls
  `__pxx_va_arg_agg`; i386 steps the walk by `RecSize` and derefs once.
  `cparser.inc`'s `__builtin_va_arg` keeps the two-deref path for exactly these
  three, so the two halves still agree with each other.

## What is missing, per target

- **aarch64.** pxx's own model carries floats as GP bits in ONE 8-slot save
  area (`__pxx_va_arg_cross`), so there is no two-class problem — but AAPCS64 is
  what gcc implements, and an aggregate >16 bytes is passed by reference there
  while pxx's fixed-param path already has a view on that. Start from
  `ABIA64CdeclArgSlot` and make the variadic tail ask it.
- **arm32 / riscv32.** `__pxx_va_arg_cross32` already steps by whole 4-byte
  words since the parent's fix (`(size + 3) & ~3`), so the receiving half needs
  only the size and one deref; the caller's tail arm in
  `ir_codegen_arm32.inc` / the riscv32 equivalent needs the same
  `IRArgRecId` read the i386 loop got. Watch the STRADDLE arm in
  `__pxx_va_arg_cross32`: it assembles an 8-byte scalar spanning the
  register/stack boundary, and an aggregate that straddles is a different
  question.

## The blocker is an ORACLE, not effort

`test-c-abi-mixed-link` is the only gate here with an outside opinion, and it
runs `x86_64` and `i386` — the two targets where gcc can produce a hosted
binary on this box. On the other three there is no gcc-compiled counterpart to
link against, so **a pxx-vs-pxx test agrees with itself whatever the convention**
— which is the sentence the parent family keeps having to relearn.

`test-c-abi-cross` does run all four cross targets and passes; it does not cover
this, which is the same "the population where two implementations can disagree"
argument. So the first piece of work is deciding what plays the oracle:
a cross gcc/binutils toolchain, a qemu-hosted link, or a hand-checked
`gcc -S` disassembly comparison of the argument setup (which is what the
fixed-param fix used before the mixed link existed).

Doing the emit without one is how the parent's sibling shipped a convention
that was wrong in both halves for months.
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

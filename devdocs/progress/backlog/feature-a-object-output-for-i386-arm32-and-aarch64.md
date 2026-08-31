---
track: A
prio: 70
type: feature
status: backlog
found: 2026-08-31
found-by: frankC
owner: ""
blocked-by: []
summary: "i386, arm32 and aarch64 have no object writer, and i386 is the one that MATTERS: x86-64 never diverged on the C-ABI question, so the x86-64 writer that landed at 41045d7b4 cannot settle decide-does-a-c-function-always-use-the-c-abi. i386 can. Shape is now known and it is NOT a port of the ELF32 ESP writer: on i386 an external call is `call dword [abs32]` through a GOT slot in our own .data, so it needs the x86-64 two-relocation treatment (operand -> .data, slot -> UND extern), whereas xtensa/riscv32 relocate a .text literal against the extern directly. Everything else -- section layout, symbol partition, the ProcCdecl export surface, R_386_32 == type 1 for both the 4-byte data and global operands -- transfers unchanged. Read the AAPCS trip-wire in feature-a-a-general-x86-64-relocatable-object-writer BEFORE doing aarch64."
---

# Object output for i386, arm32 and aarch64

Deferred by [[meta-a-pxx-produces-linkable-code]] until the x86-64 writer's
shape was known. It is now known (`writeELFRelX64General`, landed 41045d7b4),
so this is filed against a real interface rather than a guessed one.

## Do i386 first, and not because it is easiest

**It is the only one of the three that answers a question we already have.**
[[decide-does-a-c-function-always-use-the-c-abi-or-only-when-a-pascal-program-uses-it]]
is deferred because nothing can observe which arm is right — the corpus is
self-consistent before *and* after, which is how the bug survived on three
targets. x86-64 **never diverged**, so the writer that just landed proves the
machinery and settles nothing. i386 did diverge. A gcc-built i386 caller linking
a pxx i386 object turns that decision from an argument into a measurement, and
switching arms is one clause in `CProcUsesCAbi`.

## What transfers, and the one thing that does not

Transfers unchanged from `writeELFRelX64General`: the section layout, the
locals-then-globals symbol partition, the `ProcCdecl` export surface with
everything else LOCAL, the "defines nothing linkable" refusal, and the
relocation model — i386's `EmitDataRef` and `EmitGlobRef` are both 4-byte
absolute, and `R_386_32` is type 1, so `writeRela32`'s existing calls fit.

**Does not transfer: external calls.** `writeELF32Rel` relocates a `.text`
literal slot directly against the extern's UND symbol, which is right for
xtensa and riscv32. i386 emits `call dword [abs32]` through a GOT slot in our
**own `.data`** (`elfwriter.inc`, the ELF32 `DynCall` patch loop) — the same
shape as x86-64, so it needs the same **two** relocations: the operand against
`.data` with the slot offset as addend, and the slot itself against the extern.
Getting this wrong yields an object that links and jumps to address 0.

That difference is the whole reason this is not "add `machine := 3` to
`writeELF32Rel`". Decide deliberately whether the ELF32 writer grows a
per-target external-call arm or i386 gets its own writer; the parent ticket's
own diagnosis — *two writers dispatched by architecture when the discriminator
should be what the object has to carry* — applies to that choice too.

## aarch64: read the trip-wire first

[[feature-a-a-general-x86-64-relocatable-object-writer]] carries a TRIP-WIRE
section placed there by frankC on 2026-08-30, and an aarch64 object writer is
condition 1 of the two that arm it: `cparser.inc`'s aarch64 param spill is
positional while pxx's external-call path is AAPCS, and the two **coincide for
every all-integer/pointer signature** — which is why libc callbacks work today
and prove nothing. An object writer lets an external toolchain link against
pxx-compiled aarch64 code with *arbitrary* signatures, including the mixed
int/float ones where they diverge. Make that spill AAPCS, or establish by
measurement that it already is, before landing the writer.

## Umbrella

[[meta-a-pxx-produces-linkable-code]]

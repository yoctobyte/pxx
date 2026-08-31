---
track: A
prio: 70
type: feature
status: done
found: 2026-08-31
found-by: frankC
owner: frankC
blocked-by: []
summary: "i386 DONE. writeELFRel386General emits the general ELF32/i386 object and a gcc -m32 -no-pie caller links and runs it (45 pxx-emit-obj, the same caller and expected output as the x86-64 row). SHT_REL not SHT_RELA -- the i386 psABI has no addend field, so each addend is patched into Code[]/Data[] before writing; every type is R_386_32. Export POLICY is shared with the x86-64 writer through ObjPlanHostedSymbols so the two cannot drift, because if they disagreed the i386 link would be measuring the writer instead of the ABI; the FORMAT is not shared. AND IT PAID FOR ITSELF THE SAME DAY -- two findings no instrument could previously see: the C-ABI trigger FIRED and says OPTION A (with CProcUsesCAbi false, two int args arrive REVERSED and every double is -nan; with it true, all correct), recorded in the decide for the owner's ruling; and bug-a-i386-clobbers-ebx-across-a-cdecl-exported-function. arm32/aarch64 remain, split out as feature-a-object-output-for-arm32-and-aarch64 with the AAPCS trip-wire attached."
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

## RESOLVED for i386, 2026-08-31, frankC

`writeELFRel386General`. arm32 and aarch64 are split out as
[[feature-a-object-output-for-arm32-and-aarch64]] — they share no code with this
and one of them is gated on an ABI question, so carrying them here would park a
finished writer behind an unstarted one.

### What the ticket predicted, and what it got wrong

**Right:** external calls needed the two-relocation treatment. i386 emits `call
dword [abs32]` through a GOT slot in our own `.data`, so the operand relocates
against `.data` and the slot against the extern. A `machine := 3` port of
`writeELF32Rel` would have produced an object that links cleanly and jumps to
zero.

**Missed, and it is the bigger difference:** **SHT_REL, not SHT_RELA.** The i386
psABI has no addend field — `gcc -m32`, clang and tcc all emit `.rel.text` — so
every addend the ELF64 writer passes as `r_addend` must instead be patched into
`Code[]`/`Data[]` before the sections are written. Every site holds zero from
the backend, so it fills rather than overwrites, and the values are literally
the same ones the x86-64 writer passes explicitly. The test asserts `.rel.*` is
present and `.rela.*` is absent, because a `.rela` i386 object is a file
`readelf` still prints happily.

Every relocation in the object is `R_386_32` — on i386 every one of these
operands is a 32-bit absolute address, so there is exactly one type.

### The split that matters: policy shared, format not

`ObjPlanHostedSymbols` now owns the export policy for **both** hosted writers.
That is not tidiness. **If x86-64 and i386 disagreed about what an object
exports, the i386 link that exists to MEASURE the C-ABI convention would be
measuring the writer instead** — and it would look like an ABI result. The
format below it is genuinely different (ELF class, entry sizes, REL vs RELA) and
is deliberately *not* shared; merging it would have put an `if is64` at nearly
every write.

The test asserts the export surface on **both** targets rather than trusting the
shared helper, for the same reason.

### It paid for itself the same day: two findings nothing could previously see

**1. The C-ABI trigger fired, and it says option A.** Same compiler, writer,
target and `gcc -m32 -no-pie` caller; the only difference is `CProcUsesCAbi`.
False (a standalone C unit — the landed option B): `i_ii(1,2)` returns **21**,
i.e. `2*10+1`, *the integer arguments arrive reversed*, and every `double`
argument or return is **-nan**. True (Pascal `cdecl`, same signatures): all four
correct. x86-64 correct throughout, as expected — it never diverged. Full table,
and the three things it does NOT say, appended to
[[decide-does-a-c-function-always-use-the-c-abi-or-only-when-a-pascal-program-uses-it]].
**Recorded as evidence, not ruled** — the ruling is the owner's.

**2. [[bug-a-i386-clobbers-ebx-across-a-cdecl-exported-function]].** Found as a
SIGSEGV in a `printf`-using caller whose pxx function had *already returned the
right answer*, which is why it first read as a relocation bug in this writer. It
is not: an asm probe gives clobber mask `0x1` on i386 (EBX only; ESI and EDI
preserved) and `0x0` on x86-64 (rbx, r12-r15 all preserved). It bites Pascal
`cdecl` too, so it is independent of the fork above, and it sits on the
option-A side — it does not flatter the result.

Neither is a defect in this writer, and neither is a reason to hold it: the
object faithfully represents what the compiler generated, and refusing to land
would hide both. That is the platonic-code rule.

### Verified

- `make compiler/pascal26` — `converged after 1 round(s)`, `cc0ef3dc2b44`.
- `tools/gate.sh quick` — GREEN, exit 0.
- i386 object linked by `gcc -m32 -no-pie` and RUN: `45 pxx-emit-obj`, the same
  caller and the same expected string as the x86-64 row.
- The gate this must not break, re-run against `cc0ef3dc2b44`: `.asm` frontend
  `--emit-obj` (`R_X86_64_PLT32`), riscv32 (`R_RISCV_32` + `app_main`), xtensa
  (`R_XTENSA_32`), x86-64 general, and an i386 **executable** with a `libc`
  external still runs.
- `tools/doclinks.py`, `tools/docsnip.py`: 0 broken.

## Log
- 2026-08-31 — resolved, commit PENDING-COMMIT.

---
track: A
prio: 45
type: feature
status: working
found: 2026-08-31
found-by: frankC
owner: frankb-8e
blocked-by: []
summary: "THE aarch64 OBJECT WRITER IS LANDED AND VERIFIED, 2026-09-22; arm32 is what remains. aarch64 shares writeELFRelX64General's body -- e_machine, the absolute-pointer type and .rela.text construction are the only differences, so the block was lifted into ObjBuildTextRelocsX64/A64 rather than cloned a third time, with byte-identity of four saved x86-64 and i386 objects as the control. THE PSABI WAS THE WRONG PLACE TO DESIGN FROM: this backend materialises addresses from an INLINE LITERAL POOL, so three of the four relocation sites are DATA WORDS in .text (ABS64 for an 8-byte literal, ABS32 for the 4-byte `ldr w0,[pc+8]` form) and only the external call is an instruction field, where one site takes TWO relocations (MOVW_UABS_G0_NC + G1_NC). Grepping ir_codegen_aarch64.inc for the fixup arrays returns nothing -- it reaches them through the shared emitters in emit.inc -- so the sites are invisible at the file with the target name on it. Verified by tools/reloc_resolve_check.py: AGREE with pxx's own executable on 772256 bytes and 1355 relocations, 4 of 4 controls reddening it, both section bases carrying a runtime witness. --function-sections is REFUSED on aarch64 (it needs CALL26) rather than half-served. KNOWN GAP, stated because the count does not show it: the probe applies ZERO movz/movk relocations, since pxx resolves printf from its own crtl and emits no undefined symbol, so the external-call arm rests on the clang field oracle alone and wants an extern-driving probe."
---

# Object output for arm32 and aarch64

Split out of [[feature-a-object-output-for-i386-arm32-and-aarch64]] when its
i386 half landed. They share no code with it, and one of them is gated on an ABI
question, so carrying them alongside a finished writer would have parked it.

## Do the ABI question on aarch64 FIRST

The trip-wire in
[[feature-a-a-general-x86-64-relocatable-object-writer]] is the reason. On
aarch64 a pxx-compiled **C** function's prologue is positional, while pxx's own
external-call path is AAPCS. They **coincide for every all-integer/pointer
signature**, which is exactly the shape of every standard libc callback — so
`qsort`, `bsearch`, `pthread_create` and `signal` handlers work today and are
*not* evidence. They diverge on mixed int/float, because that is where AAPCS's
independent GP and FP counters stop tracking the argument index.

An object writer is what makes the falsifying test constructible: a genuinely
external caller, with a mixed int/float signature. So the honest order is —
land the writer behind, or immediately followed by, that test, and be ready for
it to go red. **The i386 measurement says to expect exactly that**: with
`CProcUsesCAbi` false, i386 reversed its integer arguments and returned `-nan`
for every double.

## What to reuse, and the one thing to check before assuming

Reuse `ObjPlanHostedSymbols` — the export policy is shared across every hosted
object writer on purpose, so a new target cannot drift from the two that exist.

**Check how the backend reaches an external before writing a line.** That was
the one thing the i386 ticket got right in advance and the ESP writer gets
differently: xtensa and riscv32 relocate a `.text` literal directly against the
extern, while x86-64 and i386 go through a GOT slot in their own `.data` and
need two relocations. arm32 uses a `movw/movt` pair loaded with the slot's
address (`elfwriter.inc`'s ELF32 `DynCall` loop), and aarch64 a `movz/movk`
pair — **neither is a plain 32-bit operand**, so both need a relocation form
this codebase has not emitted yet (`R_ARM_MOVW_ABS_NC`/`MOVT_ABS`,
`R_AARCH64_MOVW_UABS_G0_NC`/`G1_NC`). That is the real work here, and it is why
these two are not a copy of the i386 writer.

Also settle REL vs RELA per target: i386 needed SHT_REL, x86-64 and the ESP
targets use SHT_RELA. arm32's psABI is REL; aarch64's is RELA.

## The aarch64 ABI gate, settled 2026-09-22 (frankb-8e) — it was already AAPCS

This ticket asked for the aarch64 C-function parameter spill to be made AAPCS
**or** for a measurement showing it already is. It already is. The gate is
cleared and no code changed to clear it.

**What the premise said, and why it was stale rather than wrong.** The summary
described `cparser.inc`'s aarch64 spill as POSITIONAL, and it still is — that
arm is alive and load-bearing. What changed underneath the ticket is *which
functions reach it*. `cparser.inc:14825` now routes a C function with the C
convention onto `EmitParamSpillsForTarget`, whose aarch64 arm carries a genuine
AAPCS64 prologue mirrored from the external-call marshalling; the positional
arms below it serve pxx's INTERNAL convention, which is correct for a C program
calling its own functions positionally on both sides. Reading the file without
following that routing gives the ticket's answer.

### Measured, not read — and against a second toolchain

Reading my own compiler's source would have confirmed whatever I expected. The
instrument is `tools/aarch64_cabi_prologue_probe.sh`: **clang** compiles the
same signature for aarch64 and the two prologues are compared on **where each
expects each argument**.

| signature | clang | pxx |
| --- | --- | --- |
| `int a, double b, int c, double d` | `w0 d0 w1 d1` | `w0 d0 w1 d1` |
| `double b, int a, double d, int c` | `d0 w0 d1 w1` | `d0 w0 d1 w1` |
| `int a, int b, double c, double d` | `w0 w1 d0 d1` | `w0 w1 d0 d1` |
| `float a, int b, float c, int d` | `s0 w0 s1 w1` | `s0 w0 s1 w1` |
| `int a, double b, float c, int d, double e` | `w0 d0 s1 w1 d2` | `w0 d0 s1 w1 d2` |

**Why a link test was not possible, and why this is still an external opinion.**
The honest instrument is a gcc-compiled caller against a pxx-compiled callee —
the mixed-link pair under `test/`, on x86-64 — and that needs the object writer
this ticket exists to build. Comparing prologues gets a genuine second
toolchain's answer without linking. What it cannot do is prove the two agree
about the *stack*, which is why those rows are skipped rather than passed.

**The signatures are chosen so the two conventions MUST diverge.** AAPCS counts
the integer and FP banks independently; positional is one sequence. They give
the same answer for every all-integer and every all-pointer signature — the
shape of every libc callback — so `qsort`, `bsearch`, `pthread_create` and
every signal handler working today is not evidence and never was. The
discriminator is an interleaved signature.

### The positive control, which is what makes this a measurement

Disable the cdecl gate (`cparser.inc:14825`, `if False and CProcUsesCAbi...`)
and rebuild: pxx emits `w0 x1 w2 x3` — exactly the positional placement the
original premise described — and the probe reports DIFFER. So the agreement is
**caused by** the AAPCS arm rather than being an artefact of the probe, and the
ticket's account of the two conventions was accurate; only its claim about
which one is live had gone stale. Restored afterwards, binary sha back to its
pre-control value.

The probe also earned its own guard the hard way: its first two runs extracted
an EMPTY register list from both sides, and empty compares equal to empty, so
every row would have printed AGREE with a blank list. It refuses an empty or
short extraction as `BROKEN` now. Both bugs were real — `set -o pipefail`
aborting on `diff`'s exit 1, and an awk anchored at column 0 against
tab-indented asm.

### What is NOT established, so nobody inherits a conclusion without its denominator

- **Stack-passed arguments.** Past eight of a bank the argument arrives on the
  stack and the question becomes one of OFFSETS, which a register comparison
  cannot answer. The probe skips those rows explicitly, and decides to skip
  from clang's own output shape rather than from an argument count of its own.
- **By-value aggregates.** The shape that broke x86-64
  (`bug-a-c-a-by-value-struct-parameter-is-passed-as-a-pointer-to-every-c-abi-callee`)
  and the one the mixed-link pair exists for. Untested here — *as a
  correctness question*. One neighbouring question in that territory turned out
  NOT to need the writer, and it is worth knowing why before assuming the rest
  do: `bug-a-aarch64-an-aggregate-result-s-destination-is-evaluated-with-the-fp-
  argument-bank-unsaved` was parked as unreachable, and was settled the same
  evening by asking what is **emitted** rather than what runs. Declaring the
  aggregate-returning callee `extern` routes it down the C-ABI arm; a
  presence/absence differential on an instruction only that arm emits proves
  reach; and the rejection then came from reading the operand's five
  construction sites. **Nothing linked.** So before waiting on the writer, ask
  whether the question is about VALUES (it needs a caller) or about PLACEMENT
  (it may not).
- **The caller side on aarch64.** This measures a pxx CALLEE reading what a
  caller laid down. `relay_*`-shaped tests — pxx as CALLER into a gcc callee —
  fail independently and are not covered.

All three need the writer. That is now the argument FOR building it, rather
than a question blocking it.

## How this gets verified, decided BEFORE writing the writer (2026-09-22, frankb-8e)

frankuser's caution, and it is the right one to settle first: **a wrong
relocation usually still LINKS.** A successful link is a default-shaped pass in
exactly the sense that produced this ticket's own probe bug — it is what you
get when the machinery did something plausible and something wrong. So the
assertion has to be on the RESOLVED VALUE, not on `ld` returning 0.

Two constraints turned up while designing that, and both change the plan.

### 1. There is no aarch64 or arm32 linker on this box, so "link and run under qemu" cannot be built here

Checked before claiming it, because "out of reach" is an inference from a probe:

| candidate | result |
| --- | --- |
| `aarch64-linux-gnu-gcc`, `arm-linux-gnueabi{,hf}-gcc` | absent |
| `ld.lld` / `lld`, `clang -fuse-ld=lld` | absent — `invalid linker name` |
| GNU `ld` 2.46 emulations | `elf_x86_64 elf_i386 elf32_x86_64 elf_iamcu i386pep i386pe` — x86 only |
| `objcopy` targets | x86 and raw formats only |
| `qemu-aarch64`, `qemu-arm` | **present** |

So the runner exists and the linker does not. The Makefile's existing note on
`test-c-abi-mixed-link` ("no gcc cross for arm32, aarch64 or riscv32 on this
box") is still accurate, and it applies to this ticket's verification too.

### 2. clang cannot be the oracle for the relocation form pxx actually uses

pxx reaches an aarch64 external through an ABSOLUTE GOT-slot address
(`symtab.inc`, `EmitExternalCallA64`):

```
movz x16, #lo16        <- R_AARCH64_MOVW_UABS_G0_NC
movk x16, #hi16, lsl 16 <- R_AARCH64_MOVW_UABS_G1_NC
ldr  x16, [x16]
blr  x16
```

clang, for the same source, emits `adrp`/`add` — `R_AARCH64_ADR_PREL_PG_HI21`
plus `R_AARCH64_ADD_ABS_LO12_NC` — and `bl` with `R_AARCH64_CALL26`. Measured
2026-09-22 against Ubuntu clang 21.1.8. **It never emits a `MOVW_UABS`
relocation at all**, so a clang differential cannot validate the form pxx
needs. It can validate `CALL26` for internal direct calls (pxx emits 606 `bl`
in one test binary) and nothing else.

That also fixes a property of the output worth stating out loud: a
`MOVW_UABS`-relocated object is **absolute**, so it can only ever be linked
`-no-pie`. The x86-64 writer has the same property (`R_X86_64_32S`), so this is
consistency rather than a new limitation — but if a consumer ever needs PIE,
the upgrade is to move the backend to `adrp`/`add`, which is backend work and
is not in scope here.

### 3. So the instrument is resolve-and-compare against pxx's own executable

The oracle chain is: **qemu proves the executable, the executable proves the
object.** pxx's aarch64 *executable* output is already validated by running
under qemu in `test-aarch64`; the object path is a different code path over the
same emission. So:

1. build program P as an executable (`--target=aarch64`) and run it under qemu —
   that leg is the existing, independent proof;
2. build the same P with `--emit-obj`;
3. apply the object's relocations at the executable's section addresses;
4. assert the resulting `.text` is **byte-identical** to the executable's.

This answers the resolved-value question with no linker, and it fails
differently from a `readelf -r` type assertion — a wrong addend, a wrong
bit-field position inside the `movz`/`movk` imm16, or a relocation aimed four
bytes off all survive a type check and all go red here.

**Positive control, mandatory before the row is believed:** perturb one
relocation — wrong type, wrong addend, offset shifted by 4 — and the comparison
must go red for each. Without that this is a guard that has never been shown
able to fail, over a comparison of two things produced by one compiler.

**AND THOSE THREE CONTROLS TEST THE HARNESS, NOT THE CHAIN** (frankuser,
2026-09-22). The case they cannot reach: if the executable path and the object
path share the routine that computes a relocation's value, a bug in it makes
both sides wrong identically and `.text` compares equal forever. So the
harness applies relocations **with its own arithmetic, written from the
psABI** — read type, symbol, offset and addend out of the object, compute the
value, patch, compare — and the object writer emits an addend the harness must
resolve rather than a value the executable writer already computed. If the
harness turns out to need a pxx routine to do it, that is the finding and it
gets said before anything is built on it.

**The residual I owe beside that**, because the chain's first link is
execution: qemu proves the executable only on the paths it EXECUTES. A
relocation on an unexecuted path inherits nothing from that leg. The probe
program is chosen so every relocated site is on the executed path, and any
site that is not gets named.

**Two tiers of evidence, marked.** clang oracles `R_AARCH64_CALL26` for a
direct call and cannot oracle `MOVW_UABS_G0_NC`/`G1_NC` at all. The output
says which relocations have an external oracle and which rest on
resolve-and-compare, so a later reader cannot quote the weaker tier as the
stronger.

**AND THE WAY THIS DESIGN DIED AND CAME BACK IS THE TRANSFERABLE PART, not
that it came back.** Self-comparison against pxx's own executable was dropped
on real x86-64 evidence — 296,788 of 328,517 bytes differing, no `_start`, a
different export surface — and carried forward as *"it does not work"*. **The
true statement was narrower: it fails where pxx's export surface diverges, and
that is exactly the set of targets which already have a linker to compare
against.** So the measurement was correct and the QUANTIFIER was the invention,
and the tool was discarded precisely on the population that did not need it —
where an alternative existed, so nothing would ever have forced a second look.
This file's own rule about hedging the premise rather than the inference, in
its most expensive form: not an over-claimed green, but **a working instrument
thrown away.** When a design fails, record the POPULATION it failed on beside
the verdict. (frankuser, 2026-09-22.)

**BUILD ORDER, CHANGED 2026-09-22: the harness comes FIRST and is
target-generic.** It is filed separately as
[[feature-a-a-target-generic-resolve-and-compare-harness-for-emit-obj-objects]]
because xtensa and riscv32 inherit it for free — both have shipped writers
that have never had a relocation resolved — and because building it against
objects that ALREADY EXIST gives it a positive control drawn from code I did
not write. Writing the instrument and its first subject together would have
been a whole-family test certifying its own broken half.

**What it does NOT establish, and the existing precedent does not either:** that
a real linker agrees with our relocation semantics. Every ESP object in this
tree (`riscv32`, `xtensa`) is verified today by `readelf -r` assertions on
relocation type and symbol, and **nothing in the tree has ever linked or run
one**. So the resolved value has never been checked for any pxx object outside
x86-64/i386. That is a gap this ticket can close for aarch64 and arm32 and
cannot close for the psABI-conformance question, which needs a cross-linker
this box does not have.

## Umbrella

[[meta-a-pxx-produces-linkable-code]]


## The aarch64 writer, landed 2026-09-22 (frankb-8e)

`ObjBuildTextRelocsA64` in `compiler/elfwriter.inc`, dispatched from
`writeELFRelX64General`, which now serves both ELF64 machines.

**The design banked on this ticket was written from the psABI and was wrong
about three of the four sites.** It expected instruction-field relocations
throughout. What the backend actually emits, measured:

| emitter | site | relocation |
| --- | --- | --- |
| `EmitDataRef` | 8-byte literal in `.text` | `ABS64` (257) vs `.data` + DataOff |
| `EmitGlobRef` | 4-byte literal in `.text` | `ABS32` (258) vs `.data`/`.bss` |
| `EmitExternalCallA64` | `movz`+`movk` | `MOVW_UABS_G0_NC`/`G1_NC` vs `.data` |
| `ProcAddrFix` | 8-byte literal in `.text` | `ABS64` (257) vs `.text` |

`EmitLoadVarAddrA64` emits `ldr w0,[pc+8]` / `b .+8` / a 4-byte word, so the
commonest relocation in an aarch64 object is a **data word**, not a field:
1077 of 1355 in the probe. `ABS32` on a 64-bit target is what `ldr w0` asks
for and carries the overflow check that says so.

**Why grepping the backend found nothing.** `ir_codegen_aarch64.inc` mentions
none of `Fixups`, `GlobFix`, `DynCall`; it reaches them through the shared
emitters in `emit.inc`. A census of the file with the target's name on it
reports zero and is correct about the wrong set.

### One body, not a third copy

Everything but the relocation construction is ELF64 and identical for both
machines. The block was lifted into `ObjBuildTextRelocsX64` unchanged and an
`A64` sibling added beside it; `machine` and `rAbs64` carry the rest. i386
stays separate because it is a different FORMAT, which is the case that
genuinely needs its own writer.

**The control is byte-identity**, which is the reason to do it this way: four
saved objects (the reloc probe and a `--function-sections` case, x86-64 and
i386) are byte-for-byte what they were before the lift.

### How it is verified, and what is NOT verified

`tools/reloc_resolve_check.py aarch64` — AGREE with pxx's own executable on
772256 bytes, 1355 relocations, 4 of 4 controls reddening it, both section
bases carrying an independent runtime witness.

Two things had to be built for that, and both were findings:

**A pxx executable loads one `.data` in two pieces and an object cannot say
so.** Read-only at `0x4c0000` carrying `.data[0x20:]`, writable at `0x4d3270`
carrying `.data[0x00:0x20]` — two bases `0x13290` apart. The single-base vote
split 265 to 7 and refused, correctly and uninformatively. `content_regions`
locates each piece from the executable's own segments: the large one by
sliding its bytes against the section's (2 mismatches of 512 at the right
offset against 486 at the runner-up — the margin is measured, not hoped for),
the prefix by its base being EXACTLY a writable `PT_LOAD` vaddr. Neither
attestation can be influenced by the relocation values under test.

**The match has to tolerate mismatches, and x86-64 is what proves that.** An
exact compare found nothing, which reads as "these layouts do not correspond"
and is wrong: some words differ because the executable has resolved pointers
where the object has zeros, others because its build-time writer fills slots
an object leaves for runtime init. x86-64 — whose object links with GNU ld and
whose linked binary runs — shows the same differences (83 bytes and 10). A
known-good target is the only thing here that separates *this writer is
incomplete* from *this comparison is looking at the wrong thing*.

**The three perturbation controls were vacuous on the first aarch64 run** and
printed `3 of 3 controls reddened it`. They resolved without the regions, so
the UNPERTURBED comparison already differed and every perturbation reddened no
matter what it did. `control_suite` now asserts a green baseline first. A
control that cannot come out `STILL AGREES` is not a control.

### The gap, stated because the headline hides it

**The probe applies ZERO `movz`/`movk` relocations.** pxx resolves `printf`
from its own crtl and emits no undefined symbol, so `1355 relocations` covers
only `ABS64` and `ABS32`. The run now prints its own type census and says so.

The external-call arm therefore rests on ONE row: clang assembles
`movz x16,#0x1234` / `movk x16,#0x5678,lsl #16` and the harness's field
arithmetic reproduces both words exactly. That is an oracle for the FIELD, not
for which value belongs in it. A second finding fell out of it: clang's
`movz x16,#0` is `0xd2800010` and `movk x16,#0,lsl #16` is `0xf2a00010`, the
exact literals `EmitExternalCallA64` writes by hand — the backend's
hand-written encodings confirmed by an external assembler, which nothing here
did before.

**Next, and it is small:** a probe whose externs are real libc functions pxx
does not implement, so the arm is exercised end to end rather than by
assertion. `extern int some_undefined_helper(int)` already produces 2 G0 + 2
G1 relocations and 2 UND symbols on aarch64 — the shape works, it just is not
wired into a checked run.

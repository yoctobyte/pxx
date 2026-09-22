---
track: A
prio: 45
type: feature
status: working
found: 2026-08-31
found-by: frankC
owner: frankb-8e
blocked-by: []
summary: "arm32 and aarch64 still have no object writer; i386 landed separately and x86-64 before it. Both are DIVERGENT targets on the C-ABI question, so each one is a second and third oracle for a ruling the i386 measurement has already made once -- worth having, not urgent. THE aarch64 ABI GATE IS CLEARED, 2026-09-22: it asked that the spill be made AAPCS or shown already to be, and it already is. A C function on aarch64 takes EmitParamSpillsForTarget's genuine AAPCS64 arm -- measured against clang as an external oracle, not read: for f(int,double,int,double) pxx's prologue reads w0/d0/w1/d1, byte-for-byte clang's placement, where positional would be w0/x1/w2/x3. Five register-passed signatures agree, including reordered, float and mixed; tools/aarch64_cabi_prologue_probe.sh is the instrument and its positive control is to disable the cdecl gate in cparser.inc, which makes pxx emit exactly w0/x1/w2/x3 and the probe report DIFFER. STILL UNSETTLED and NOT claimed: stack-passed arguments (an offset question the register probe skips by design) and by-value AGGREGATES -- both need the writer plus a gcc-compiled caller, so the falsifying test remains the reason to build it. Expect the shape to follow i386's, not the ESP writer's: check how each backend reaches an external before assuming."
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
  and the one the mixed-link pair exists for. Untested here.
- **The caller side on aarch64.** This measures a pxx CALLEE reading what a
  caller laid down. `relay_*`-shaped tests — pxx as CALLER into a gcc callee —
  fail independently and are not covered.

All three need the writer. That is now the argument FOR building it, rather
than a question blocking it.

## Umbrella

[[meta-a-pxx-produces-linkable-code]]

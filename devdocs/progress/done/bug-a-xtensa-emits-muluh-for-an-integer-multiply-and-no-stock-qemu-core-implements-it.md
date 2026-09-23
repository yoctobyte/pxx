---
slug: bug-a-xtensa-emits-muluh-for-an-integer-multiply-and-no-stock-qemu-core-implements-it
track: A+S
type: bug
prio: 40
status: done
owner: ""
created: 2026-09-23
found-by: frank (adding the xtensa arm to the signal tests)
blocked-by: []
summary: "CLOSED 2026-09-24 -- THE MITIGATION SHIPPED BEFORE THIS TICKET WAS FILED AND I DID NOT GREP FOR IT. `--xtensa-soft-mulhigh` expands high(a*b) into a shift/mask/mull sequence with no MUL32_HIGH, it is wired into every existing test-xtensa row, and defs.inc has carried the same measurement this ticket re-derived (no qemu-xtensa core implements MUL32HIGH, all eight SIGILL) since 2026-08-29 under feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle. So this ticket's own stated retirement condition -- a hosted xtensa program that multiplies and runs to completion under a stock core -- was ALREADY MET: measured at close, `i*j` then WriteLn prints 21 and 123456 correctly under bare `qemu-xtensa`. The flag is opt-in DELIBERATELY, because it is a property of the emulator and of no chip (every shipping LX6/LX7 has MUL32_HIGH), so a verdict taken under it must name it -- it LABELS the divergence rather than removing it. WHAT LANDED HERE: the three signal tests this ticket held out (test_signal_num, test_signal_siginfo, test_signal_bss_alias) are now wired into test-xtensa, byte-identical to the x86-64 oracle, with a positive control proving the rows can fail. THE HOLD-OUT REASON WAS THE DEFECT: it was measured without the flag its five sibling signal rows already passed, so the instrument was correct about a configuration nothing in this target uses. THE PERF HALF MOVED and is the only live work: bug-o-every-integer-multiply-emits-four-multiplies-on-the-32-bit-backends-and-one-is-enough. The width half stays CLOSED -- do not narrow the binop type; {$Q+} overflow detection is built on the wide evaluation."
---

# xtensa emits `muluh` for an integer multiply, and no stock qemu core implements it

Found 2026-09-23 while adding the xtensa arm to the signal tests for
[[bug-a-xtensa-tkill-syscall-number-is-unlocated]]. That ticket is closed — the
syscall number was the whole of it — and this is the **residual**, recorded so
"the tests still do not run" has an owner rather than sitting in a resolution
nobody re-reads.

## Reproduction — three lines, no signals involved

```pascal
program m;
var i, q: Integer;
begin i := 7; q := i * 3; WriteLn(Chr(48 + q)); end.
```

```
$ pascal26 --target=xtensa --platform=posix m.pas m && qemu-xtensa m
qemu: uncaught target signal 4 (Illegal instruction) - core dumped
```

## What works and what does not, which is what names the instruction

| operation | xtensa/posix | riscv32/posix |
| --- | --- | --- |
| `WriteLn('hello')`, `WriteLn('a')` | **ok** | ok |
| `i shr 1` | **ok** | ok |
| `i div 10`, `i mod 10` | **ok** | ok |
| `i * 3` | **SIGILL** | ok |
| `WriteLn(i)` for `Integer` or `Int64` | **SIGILL** | ok |

**Division and modulo work and multiplication does not**, which is the opposite
of the guess anyone would make (xtensa DIV32 is also optional), and it is what
points at the instruction rather than at the operation class.

## The faulting instruction is the one AFTER `mull`

`qemu-xtensa -d in_asm`:

```
0x0804eb59:  mull	a8, a4, a2
0x0804eb5c:  ???
qemu: uncaught target signal 4 (Illegal instruction)
```

`mull` **decodes**, so MUL32 is present in the core. The undecodable instruction
is at +3. Bytes read out of the image at that offset:

```
20 84 82   mull  a8, a4, a2
20 94 a2   <- faults
30 a4 82
20 b5 82
```

`20 94 a2` is xtensa RRR with `op0=0, op1=2, op2=10, r=9, s=4, t=2` — **`muluh`**,
the unsigned-multiply-high of the **MUL32_HIGH** option, which is a *separate*
configuration option from MUL32. That is why `mull` is fine and this is not.

**No stock core model implements it.** Measured, all seven that
`qemu-xtensa -cpu help` offers, plus the default:

```
dc232b dc233c de212 de233_fpu dsp3400 lx106 sample_controller (default)
```

every one SIGILLs on the same program. **So this is not a `-cpu` fix**, and a
ticket proposing one has not measured it.

## The sequence says the operands are being treated as 64-bit

`mull a8,a4,a2 / muluh a9,a4,a2 / mull a10,a4,a3 / mull a11,a5,a2` — four
multiplies and a high word is a **64x64 expansion**, and both operands here are
declared `Integer`. So the high word is computed for a multiply whose declared
result is 32 bits.

**DO NOT FILE THAT HALF AS A DEFECT WITHOUT DECIDING IT.** CLAUDE.md records
that the native *float* evaluation type is `Double` and that evaluating wider
than the declared type is *the architecture, not a defect* — the same may be
true of integers, in which case the 64-bit expansion is correct and the only
bug is reaching an optional instruction. **The test is the same one that rule
gives: store the result in its DECLARED type and compare THAT.** If a 32-bit
product is correct, the widening is latitude.

What is NOT latitude either way: reaching an **optional ISA feature** for a
multiply. `muluh` needs MUL32_HIGH, and a target this backend supports may be
configured without it — so a narrower lowering (or a runtime/soft fallback) is
wanted on portability grounds regardless of how the width question is decided.

## Why it stayed invisible, and the scope of that

**ESP32 LX6/LX7 have MUL32_HIGH**, and the ESP profile does not run under stock
qemu-user at all — `tools/esp_run.sh` selects Espressif's
`qemu-system-xtensa` (`~/.espressif/tools/qemu-xtensa/*/qemu/bin/`) for
`-M esp32s3`. So every xtensa row the suite actually executes goes through an
emulator whose core has the option, and the hosted profile is the only one that
can see this.

This is the house pattern from CLAUDE.md — *"a whole defect class is
structurally invisible to the instrument that would normally catch it"* — with
the axis being **which emulator**, not which host word size. **Before ranking an
xtensa result, say which qemu ran it**: stock `qemu-xtensa` (user-mode, no
MUL32_HIGH) and Espressif `qemu-system-xtensa` (`-M esp32s3`) are different
instruments and they disagree on this program.

## Consequence to record, because it is bigger than one test

`--target=xtensa --platform=posix` **cannot run a program that prints a
number.** Integer-to-decimal conversion multiplies, so the wall is not limited
to source that contains a `*`. Any hosted-xtensa assertion built on printed
output is unreachable today, which is a plausible reason the hosted xtensa
corpus is as thin as it is — *that last clause is a hypothesis and is not
measured here; do not quote it as a cause.*

Three tests are in exactly this position as of this ticket:
`test_signal_num.pas`, `test_signal_siginfo.pas`, `test_signal_bss_alias.pas`
now **build** for xtensa and print a prefix (`usr1=`, `segv code=`, `hit=`)
before dying — so the signal is delivered and the handler runs, and the SIGILL
is downstream of everything they were written to test. **They are deliberately
NOT wired into the suite for xtensa**; wiring them would add three red rows for
a reason that has nothing to do with signals.

## Positive control for whoever fixes this

`i * 3` with `Integer` operands must run to completion under **stock**
`qemu-xtensa` with no `-cpu` argument. Assert the VALUE, not just the exit
status — a lowering that avoids `muluh` by computing the wrong product would
pass an exit-code row. And re-run the three signal tests above: they are the
population that wants this, and each prints a number.

# Umbrella

[[meta-a-pxx-produces-linkable-code]]

---

# Investigated 2026-09-24 (frank) — the WIDTH question is CLOSED, and the answer is "leave it alone"

This ticket left two questions open and cautioned against filing the first as a
defect. **It is now answered, and the answer is the opposite of the tempting
fix.** Recorded here specifically so the next seat does not "fix" this by
narrowing the multiply.

## The widening is target-independent, deliberate, documented, and load-bearing

**riscv32 emits the IDENTICAL expansion** — so this was never an xtensa quirk:

| | sequence |
| --- | --- |
| xtensa | `mull a8,a4,a2` / `muluh a9,a4,a2` / `mull a10,a4,a3` / `mull a11,a5,a2` |
| riscv32 | `mul t2,t0,a0` / `mulhu t3,t0,a0` / `mul t4,t0,a1` / `mul t5,t1,a0` |

riscv32 survives only because **RV32M always provides `mulhu`**, while xtensa's
**MUL32_HIGH is an optional configuration option** — separate from MUL32, which
is why `mull` decodes and `muluh` does not.

**The IR says it plainly.** `PXXDBG=a.ir:Mul` for `q := i * j`, all three
`Integer`:

```
0: load_sym  tk=1  [sym=i]      tk=1  = tyInteger  (4-byte signed)
1: load_sym  tk=1  [sym=j]
2: binop  a=0 b=1 c=72 tk=13    tk=13 = tyInt64    (8 bytes)
3: store_sym a=4 b=2 tk=1 [sym=q]
```

Operands `tyInteger`, destination `tyInteger`, **binop `tyInt64`**.

**And it is the documented architecture, not an accident.**
`ir_codegen.inc:6106`, `EmitOvfCheckNarrowX64`:

> *The binop was computed at 64-bit register width on sign/zero-extended
> operands, so rax holds the mathematically exact result and the 64-bit OF/CF
> never fire for a 32-bit wrap (bug-a-qplus-misses-32bit-overflow). The check is
> therefore a range test.*

So the wide evaluation is **what `{$Q+}` overflow detection is built on**: the
exact result exists, and the check is "re-extend the low width and compare". This
is the integer analogue of CLAUDE.md's *"DOUBLE IS THE NATIVE EVALUATION TYPE …
an expression being typed or evaluated at double width is the architecture, not a
defect"*, and it has a mechanism depending on it.

**DO NOT NARROW THE BINOP TYPE.** It would silently remove the exact-result
property `{$Q+}` depends on, on every target, to save instructions on three.
That is the change this section exists to prevent.

## What IS measured, and what it costs

The high half really is dead for a 32-bit destination — the store is one 32-bit
word:

```
add a1,t3,t4     ┐ high half assembled...
add a1,a1,t5     ┘
mv  a0,t2
lw  t0,8(t0)
sw  a0,0(t0)     <- only a0 (the LOW word) is stored; a1 is never used
```

Four multiplies and two adds where one `mul` would do, **on every integer
multiply, at every declared width**. Measured on riscv32 by counting multiply
instructions in the executed trace, `Integer*literal`, `Integer*Integer`,
`Int64*Int64` and `SmallInt*SmallInt` — **all four emit 4**. Negative control: a
program whose only change is `+` instead of `*` emits **0**, so the instrument is
counting the expression and not the RTL.

**This is a cost that is FREE on the primary target and paid only by the
secondaries** — a 64-bit `imul` on x86-64 is one instruction. That is CLAUDE.md's
measured-on-x86-64 blind spot arriving in a performance decision rather than in a
correctness one.

## So the defect is narrower than this ticket's title, and it is not the width

**The lowering assumes an OPTIONAL ISA feature with no fallback.** MUL32_HIGH is
configurable on xtensa; the backend emits `muluh` unconditionally. That is true
regardless of how the width question is decided, and it is what should be fixed.

Options, and the choice needs a decision this ticket cannot take alone:

1. **A MUL32_HIGH-free high-word path on xtensa** (16x16 partial products, or a
   soft helper). Correct everywhere, costs code size on a flash-constrained
   target. Note `mul16u`/`mul16s` are ALSO optional — do not assume them.
2. **A consumer-aware narrowing**: emit only the low multiply when the result is
   provably consumed at <= 32 bits. Fixes the wall AND the cost on all four
   32-bit targets, and does NOT touch the binop's type, so `{$Q+}` keeps its
   exact result wherever the result is actually used wide. **This is the one to
   price first** — it is the only option that is a win rather than a trade.
3. **Target-capability gating** — a flag for cores without MUL32_HIGH. Cheapest,
   and it pushes the problem onto whoever builds for such a core.

## Scope correction to this ticket's own framing

Its summary says the two questions "have different owners" and names the width
one as possibly deliberate. **It is deliberate — confirmed — so that half is
closed and should not be re-opened.** What remains is one Track A question
(option 2 above, which is an optimisation with a correctness precondition) and
the pre-existing fact that hosted xtensa cannot multiply under stock qemu.

**Priority unchanged.** ESP is unaffected (Espressif's emulator and LX6/LX7 have
MUL32_HIGH), so this still blocks only the hosted-xtensa profile — but option 2
would make it a performance win on riscv32, arm32 and i386 as well, which is a
better reason to do it than the wall is.

---

# Closed 2026-09-24 (frank) — the mitigation predates the ticket, and the hold-out reason was the defect

**Read every section above this line as the 2026-09-23/24 report, not as current
state.** Two of them are now false and are left in place because this file is
append-only below the summary: *"Consequence to record"* (hosted xtensa cannot
print a number) and its claim that three tests are *"deliberately NOT wired
into the suite"*. Both are true only of the **default** lowering.

## What I failed to do

`--xtensa-soft-mulhigh` exists, ships, and is passed by **every**
`test-xtensa` row. `compiler/defs.inc` documents it beside `XtensaSoftDivide`
and carries the *same measurement this ticket re-derived from scratch* —

> *It exists because NO qemu-xtensa core implements MUL32HIGH: measured
> 2026-08-29 against qemu-xtensa 10.2.1, all EIGHT cores it exposes SIGILL on
> `muluh` while all eight run quos/rems.*

— under [[feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle]]. The
`test-xtensa` recipe says it outright: *"It is required — without it integer
formatting takes an illegal instruction on qemu's core."* And
[[bug-a-hosted-xtensa-diverges-from-the-oracle-on-21-cross-programs]] (`done/`,
2026-08-31) records the standing convention: hosted-xtensa sweep conditions are
`--platform=posix --xtensa-soft-mulhigh`, both flags load-bearing.

I re-derived the instruction encoding, the eight-core census and the MUL32 /
MUL32_HIGH split, and filed it at p40, without grepping for a mitigation.
**One `grep -rn soft-mulhigh compiler/` would have ended it.** That is
CLAUDE.md's crash-course rule — *"before proposing a mechanism, grep for it"* —
and my option 3 (*"target-capability gating — a flag for cores without
MUL32_HIGH"*) was a proposal to build the thing I was already standing in.

## The retirement condition was already met

This ticket's own condition, measured at close under bare `qemu-xtensa`, no
`-cpu`:

```
$ pascal26 --target=xtensa --platform=posix --xtensa-soft-mulhigh m.pas m
$ qemu-xtensa m
21
123456
```

Asserting the **values**, as the ticket's positive control demanded, not the
exit status. Without the flag the same source is `SIGILL`, rc=132 — so the
mitigation is what moved, and the wall is real and configuration-dependent.

## The hold-out reason was the actual defect, and it generalises

The three signal tests were held out **because they print a number**. That was
measured without the flag — while the five sibling signal rows sitting directly
above them in `test-xtensa` (`sigdfl`, `sigcb`, `sigalt`, `pcrw`, `sprw`) all
pass it. So the measurement was honest, reproducible, and **about a
configuration nothing in this target uses**: the population was the default
lowering, and the subject was a test suite that never runs the default lowering.

This is CLAUDE.md's *"every instrument that lies, lies by being CORRECT ABOUT
SOMETHING ELSE"*, with the something-else being **a flag the surrounding rows
already set**. The cheap discriminator I skipped: *how do the tests next to this
one invoke the compiler?* Not a fact about xtensa, about multiplies, or about
qemu — a fact about the neighbours, which is where the answer was.

**Worth promoting only if it recurs**: banked here and in the logbook, not in
CLAUDE.md, per its own promotion test — one instance, one subsystem.

## What landed in the closing commit

- **Three rows wired into `test-xtensa`**: `test_signal_siginfo`,
  `test_signal_num`, `test_signal_bss_alias`, with the flag, asserting the same
  literal expected values the i386/aarch64/arm32/riscv32 rows use so the five
  targets stay diffable against each other.
- **Verified**: all three byte-identical to the x86-64 build of the same source;
  run through `tools/run_target.sh` + `expect_same.sh`, not by hand.
- **Positive control**: a deliberately wrong expected value makes the row report
  `MISMATCH` and exit 1, and `od -c` confirms `run_target.sh` emits real output
  rather than skipping — so the rows can fail, in both of the ways they could
  have been vacuous.

## What is still open, and it is not this

[[bug-o-every-integer-multiply-emits-four-multiplies-on-the-32-bit-backends-and-one-is-enough]]
— the perf half, which is real, measured, and on four targets rather than one.
The **width** half stays closed: do not narrow the binop's type, because `{$Q+}`
overflow detection is built on the wide evaluation. The section above headed
*"the WIDTH question is CLOSED"* is the evidence for that and remains current.

## Log
- 2026-09-24 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

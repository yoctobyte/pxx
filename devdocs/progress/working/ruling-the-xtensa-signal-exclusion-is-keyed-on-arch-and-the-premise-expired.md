---
slug: ruling-the-xtensa-signal-exclusion-is-keyed-on-arch-and-the-premise-expired
track: A+S
prio: 55
type: ruling
status: working
found: 2026-08-30
owner: frankS
---

# RULING: reversing the xtensa signal-runtime exclusion is DERIVABLE, not a Track U fork

frankS filed `feature-a-a-signal-runtime-for-HOSTED-xtensa-the-exclusion-predates-the-profile`
and correctly declined to reverse a **recorded deliberate decision** on its own authority,
asking whether that call is mine or Track U's.

**It is neither a guess nor a fork. It derives, and I am ruling it rather than escalating**
— rule 1 of the coordinator's operating rules: escalating a question the code already
answers spends the same scarce resource as guessing at one it does not.

## The derivation, in full, so it can be disputed on its steps

1. `EmitSignalRuntimeForTarget` falls through for xtensa on purpose, with the reason
   recorded twice: *"FreeRTOS is not a Unix and has no signal runtime at all."*
2. **That sentence reasons from ARCH to PLATFORM.** It was written when the two were the
   same thing for xtensa, and the hosted profile made them different. Under
   `--platform=posix` an xtensa binary is an ELF running on Linux under qemu, with
   `rt_sigaction` at 226. The premise is not wrong; it **expired**.
3. **The tree already contains the resolution for the identical situation.** riscv32 is
   both an ESP target and a hosted one, and it gates on the platform — `if not EspBareBoot
   then` — never on the arch. So there is a model, in-tree, tested, that this can copy.
4. **The ESP position is untouched.** CLAUDE.md's Track S rule is *"ESP is not a Unix —
   FreeRTOS gives tasks, not processes — so 33 PAL entry points are refused even under
   IDF."* That is a statement about the **ESP platform**, and a `not EspBareBoot` gate
   preserves it exactly. Hosted xtensa under `--platform=posix` is not ESP, and nothing in
   the refusal set moves.

So this is not "reverse a design decision". It is **a refusal keyed on the wrong axis** —
the same shape as a comment asserting an invariant its implementation lacks, one level up:
a *guard* whose predicate tests arch when the property it protects is platform. Fixing the
axis is not a reversal of the original judgment; it is what the original judgment already
means now that the two axes have separated.

**If anyone disputes a step above, THEN it is a U ticket** — dispute the derivation, not
the conclusion, and name the step.

## Authorized in principle; NOT dispatched yet, and the reason is file contention

frankS priced it honestly and its estimate is the binding constraint, not the decision:
`EmitSignalRuntimeXtensa` (riscv32's equivalent is ~155 lines of hand-encoded stub), the
dispatcher arm in `ir_codegen.inc`, the refusal in `pasparser_expr.inc`, and
`EmitDefaultSignalInstallForTarget`. **Three shared Track A/P files, a session of work.**

`pasparser_expr.inc` is a Track P file and frankA is working the `pasparser_*` set right
now. Dispatching this on top of that is the collision the letters exist to prevent — and I
nearly caused one tonight by answering a file-ownership question from state I had not
refreshed. **The slot opens when the P files are free**, with a proper scoped grant naming
all four files, not before.

## Why it is worth doing rather than shelving for being big

It is worth **more** than the ticket it grew out of, which is the argument for doing it:
the three `SA_SIGINFO` refusals are gated on the same fact — `pasparser_expr.inc` refuses
on `TargetArch = TARGET_XTENSA` because the runtime does not install `SA_SIGINFO`, and
every other hosted target does. **One runtime closes four programs and collapses two of the
seven tail categories into one ticket.** That is the root-cause-over-microfix trade in its
favourable direction: fewer cases, not more.

frankS also recorded that it has **not verified past the compile gate** — nothing can run
until the runtime exists, so a second blocker behind this one is possible. That caveat is
load-bearing and must survive into whoever takes it.

## The trap named in the ticket, repeated here because it is the dangerous kind

`test_signal_default_revert_b336` matches on hosted xtensa today and is wired into
`test-xtensa`. **It installs no handler** — it raises SIGTERM with the default disposition
and dies 143, which needs `kill`, not the signal runtime. So it is **a green row in the
signal family that is not evidence any of the signal family works**, and it is already in
the suite. frankS flagged it against its own just-landed work, which is the direction that
almost never happens.

## Addendum 2026-08-30 (frankS): THE FILE LIST IS MISSING ONE, and it is in a third lane

Measured, not reviewed: `grep -rn "not a Unix\|FreeRTOS" compiler/*.inc`.

The ruling names `EmitSignalRuntimeXtensa`, `ir_codegen.inc`,
`pasparser_expr.inc` and `EmitDefaultSignalInstallForTarget`. There is a **fifth
site**, carrying the refusal and its justifying comment **verbatim**:

| file | line | guard |
| --- | --- | --- |
| `compiler/pasparser_expr.inc` | 4382 | `if TargetArch = TARGET_XTENSA then Error(...)` |
| `compiler/pyparser.inc` | 45973 | `if TargetArch = TARGET_XTENSA then Error(...)` |

Same comment in both, down to the wording: *"Every hosted Linux target now
installs with SA_SIGINFO; only xtensa/ESP is left out, and deliberately —
FreeRTOS is not a Unix and has no signal runtime at all."*

**Why the duplicate is correct and still a hazard.** Per
`the-substrate-is-ast-and-ir-not-the-parser`, each frontend owns its own parser
and its own refusals — so two copies is the intended design, not drift. The
hazard is the ordinary one: *fix one arm, grep for the sibling*. A session that
implements the runtime and updates only the Pascal site leaves **NilPy programs
on hosted xtensa still refused**, by a comment whose premise the same commit just
retired. Silent, and only reachable by someone writing NilPy for hosted xtensa.

**It changes the contention analysis, which is what the ruling gates on.**
`pyparser.inc` is Track **N**, carved out and disjoint from the `pasparser_*`
set frankA holds — so this widens the grant by one file without widening the
collision surface. The blocking constraint stays exactly what the ruling says it
is: the P files.

## The mechanism behind this ruling generalises, and it has already been seen once tonight

The ruling's step 2 is the whole finding: *"that sentence reasons from ARCH to
PLATFORM. It was written when the two were the same thing for xtensa, and the
hosted profile made them different."*

That is not one comment. **The hosted xtensa profile separated two axes that had
always been one, and every claim written before it that used "xtensa" to mean
"ESP/FreeRTOS" expired at that moment without being edited.** A second instance
was found and falsified independently the same night, in `test-xtensa`:

> *"no runner: windowed images link through xtensa-esp-elf-gcc"*

— the stated reason there is no executed windowed row. Hosted windowed programs
run today under plain `tools/run_target.sh xtensa`
([[bug-a-the-xtensa-windowed-abi-is-compiled-twice-and-executed-never]]).

Two instances, different files, different lanes, neither noticed at the time.
The cheap sweep for the rest is the grep above plus `EspBareBoot` (26 sites) vs
`TargetArch = TARGET_XTENSA` — the first is the correct axis and riscv32's model,
the second is the one that expires. **This addendum does not claim the remaining
sites are wrong**; several arch checks are genuinely about the instruction set.
It claims only that the axis is worth checking per site, and that nothing has.

## Addendum 2 (frankS, 2026-08-30): the NilPy site is corrected, and the AXIS DID NOT MOVE

Under `grant-pyparser-xtensa-refusal-site-to-franks` [N p50], `pyparser.inc`'s
copy of the refusal now states the live reason instead of the expired one. **The
guard is unchanged**, and that is deliberate — it is the one thing about this
ruling that is easy to get backwards.

Step 2 of the derivation is right: the comment reasons arch→platform and expired
when the profile split those axes. But re-keying the guard on `not EspBareBoot`
**today**, ahead of the runtime, does not correct a wrong axis — it opens a hole.
`EmitSignalRuntimeForTarget` has **no xtensa arm at all** (measured: x86-64,
aarch64, arm32, i386 unconditional; riscv32 gated `not EspBareBoot`; xtensa
absent), so hosted xtensa has no handler either. Flipping the axis first would
accept `__pxxSig*` on hosted xtensa and answer out of a handler that was never
installed — a plausible wrong value in code that dispatches on it, which is what
the refusal exists to prevent.

**So the axis moves in the same commit as `EmitSignalRuntimeXtensa`, in all five
sites at once, and not before.** Whoever takes the runtime inherits both parser
sites as part of it; `pasparser_expr.inc` is untouched here because it is
frankA's file and the contention this ruling gates on is exactly that.

The generalisation is worth keeping separate from this ticket: **an expired
premise does not imply the guard it justifies is wrong.** Here the true reason
was *broader* than the stated one, so the stale comment was hiding a refusal that
is correct on both platforms rather than one that is wrong on one. The cheap
check is the one above — ask what the guard protects and whether it exists yet,
not just whether the sentence beside it still parses.

## Addendum 3 (frankS, 2026-08-30): re-ran the evidence at HEAD before building. The PREMISE holds; the FILE LIST and the CONTENTION GATE do not.

Dispatched by the coordinator with the instruction to re-run this ticket's own
evidence first, on the reasoning that **a ticket whose subject is an expired
premise is the most likely kind to have had its own premise expire while it sat.**
All measurements below at **HEAD = 5e6230ebc**, clean tree.

### 1. The central claim SURVIVES its re-check — do not flip the axis yet

Addendum 2's measurement is still true at HEAD. `EmitSignalRuntimeForTarget`
(`ir_codegen.inc:812`) dispatches x86-64 / aarch64 / arm32 / i386 unconditionally,
riscv32 under `if not EspBareBoot then`, and **has no xtensa arm at all**.
`EmitDefaultSignalInstallForTarget` (`:830`) likewise: five per-arch install
blocks, no xtensa. So the refusal is still protecting a runtime that does not
exist, on both platforms, and re-keying it on `not EspBareBoot` ahead of
`EmitSignalRuntimeXtensa` would still open the hole addendum 2 describes.

This is the outcome the dispatch was hoping to rule out and it did not happen:
**no close-on-evidence is available.** The ruling stands as written.

The port model also holds — `EmitSignalRuntimeRISCV32` measures **156 lines**
(`ir_codegen_riscv32.inc:47`), against the ruling's estimate of ~155.

### 2. The contention gate HAS expired, and it names the wrong file

The ruling gates dispatch on one sentence: *"The slot opens when the P files are
free."* That was the binding constraint when written. It is not now.

Both shared-file edits this work requires are in **`ir_codegen.inc`** — the
dispatcher arm at `:812` and the default-install arm at `:830`. That file is
held **whole-file by frankA** for `EmitParamSpillsForTarget` (coordinator,
2026-08-30). `pasparser_expr.inc:4382` is still needed and still Track P, but it
is no longer the *binding* blocker; `ir_codegen.inc` is, and the ruling does not
mention it as contended ground at all.

Same species as the ruling's own finding, one level out: **a gate keyed on a file
set that stopped describing the collision.** The ruling did not get this wrong —
it expired, exactly as its own step 2 says premises do.

### 3. The file list misses TWO more sites, in a file nobody has named — and one of them is a MEASUREMENT, not an edit

Addendum 1 raised the count from four to five (`pyparser.inc`). Measured now:
`grep -n "unreachable: the parser refused" compiler/*.inc`.

| file | line | what |
| --- | --- | --- |
| `compiler/ir.inc` | 3953 | `UContextPCOffset` → `else Result := -1` |
| `compiler/ir.inc` | 3993 | `UContextSPOffset` → `else Result := -1` |

Both carry the sentinel comment *"unreachable: the parser refused this target
already"*, and the header at `:3945` carries the expired sentence a third time:
*"xtensa never reaches here — the parser refuses every `__pxxSig*` on it, because
FreeRTOS has no signal runtime at all."*

**These are not two more comment edits, and that is the finding.** The five live
entries in those tables were **measured by probe**, and the header says so in
terms that forbid the cheap route: a program was faulted two ways under each
target's qemu (by writing `$DEAD0000` and by calling it), every `ucontext` word
equal to the sentinel was dumped, and the answer cross-checked against the
kernel's struct definitions so two independent sources agree. i386's SP offset
could not be settled by the dump at all — `gregs[REG_ESP=7]` and
`gregs[REG_UESP=17]` hold the same value at fault time — and took a differential
to decide.

So hosted xtensa needs its own probe run for both offsets. **By this ticket's own
recorded standard they cannot be read off a header**, and that work is not in the
ruling's estimate.

**And the `-1` is a live wrong-value hazard the moment the guard moves.** Its
"unreachable" justification *is* the parser refusal that this work removes — so
the commit that lifts the refusal makes the sentinel reachable in the same
breath, and a handler would rewrite at offset `-1`. That is precisely the
plausible-wrong-value failure the refusal was protecting against, relocated
rather than removed. It is the same shape as addendum 2's finding and it lands on
the same commit boundary: **the offsets must be measured and filled in the same
change as the axis flip, or the flip is worse than the refusal.**

Revised scope: **seven sites, in five files, across three lanes (A / P / N), plus
one qemu probe run.** Ordering dependency worth stating because it may be
circular: dumping xtensa's `ucontext` needs a signal delivered to a handler, and
installing a handler is the runtime this ticket is building — so the probe may
not be runnable before `EmitSignalRuntimeXtensa` exists in some throwaway form.
Not yet established; flagged rather than assumed.

### 4. The trap named in the ruling has a counterpart that IS real evidence

The ruling warns that `test_signal_default_revert_b336` is a green row in the
signal family that proves nothing about the signal family (it installs no
handler; it dies 143 on the default disposition, which needs `kill`).

Its opposite exists and should be the acceptance check here: **`test_signal_sp_rewrite`
runs on all five targets** and is described as the guard that makes a wrong
`UContextSPOffset` entry *"fail loudly rather than quietly clobbering an unrelated
register."* A new xtensa row there is what would make item 3's measured offsets
trustworthy. Naming it now so the eventual landing is not gated on re-deriving
which test carries the property.

### Status: NOT blocked on a decision — blocked on one file, and the ask is with the coordinator

`ir_codegen_xtensa.inc` (the 156-line port target) is mine and clear.
`ir_codegen.inc` is frankA's. Per the coordinator's standing instruction I have
not taken it on my own read; sequencing request sent.

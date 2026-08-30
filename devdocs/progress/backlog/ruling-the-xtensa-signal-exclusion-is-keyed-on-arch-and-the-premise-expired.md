---
slug: ruling-the-xtensa-signal-exclusion-is-keyed-on-arch-and-the-premise-expired
track: A+S
prio: 55
type: ruling
status: open
found: 2026-08-30
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

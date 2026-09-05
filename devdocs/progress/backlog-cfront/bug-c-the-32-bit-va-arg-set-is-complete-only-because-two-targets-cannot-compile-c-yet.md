---
slug: bug-c-the-32-bit-va-arg-set-is-complete-only-because-two-targets-cannot-compile-c-yet
track: C
prio: 35
type: bug
blocked-by: []
status: backlog
created: 2026-08-31
summary: "HALF DISCHARGED 2026-09-04, half still armed, and the ticket's own hard requirement was met. cparser.inc's four `TargetArch in [TARGET_I386, TARGET_ARM32, TARGET_RISCV32]' tests now read `[..., TARGET_XTENSA]': that widening landed in 233e693bb, THE SAME COMMIT as the xtensa C entry stub, which is what this ticket asked for. So xtensa can no longer silently take the 8-byte-slot else arm. Verified by running, not by reading: test/c_crtl_syscall_guarded_bodies.c and four vararg probes build and run under qemu-xtensa and match the gcc oracle. NOTE the widening alone was NOT sufficient -- with the set correct, 64-bit variadic arguments were still wrong for two further reasons (the direct-call ladder never classified a tail argument, and the caller's even-word pad disagreed with the walk's packed align=4), fixed in 7574a5f8d; membership in the 4-byte set is necessary and does not by itself make a target's varargs correct. wasm32 IS STILL ABSENT from the set and the trigger stays armed for it, gated only by bug-c-no-c-program-entry-stub-for-wasm32-so-no-c-program-can-target-it -- whoever lands that stub owes the same one-line widening in the same commit. THE TRIGGER IS NOW EXECUTABLE (2026-09-05, frankC): tools/c_va_arg_every_target.sh asserts, per target, that a build matches gcc exactly and that a REFUSAL names the C entry stub — the second arm being what stops a frontend broken for all cross targets from turning the check green. Proved a guard by ablation: TARGET_RISCV32 removed from the four sets made riscv32 print 0.00 where gcc says 2.50, which is the silent-wrong-values defect this ticket describes. NOTHING WAS WIDENED — the set is untouched and wasm32 stays unmeasurable by construction. The `Cross (aarch64)` comment residual at cparser.inc:2093 is also done -- the sibling at :2171 was reworded when xtensa landed and this one was missed."
---

# The 32-bit `va_arg` set is complete only because two targets cannot compile C

Found 2026-08-31 (frankwasm) auditing single-arm/enumerating `TargetArch` tests
for wasm32 holes — the population frank-rust's `refactor-a-target-dispatch-chains-fail-open`
sweep explicitly did not cover (it audited 27 dispatch *chains*; this is a
*set membership* test).

## Measured, binary `25178873db17`

A C program using `va_start`/`va_arg`/`va_end`:

| target | result |
| --- | --- |
| i386, arm32, riscv32 | **ok** — in the set, 4-byte slots |
| aarch64, x86-64 | **ok** — else branch, 8-byte slots, correct for both |
| **xtensa** | `error: C program entry stub not implemented for this target yet` |
| **wasm32** | `error: C program entry stub not implemented for this target yet` |

So the set names exactly the 32-bit targets that can compile C, and it is
**complete and correct as it stands.** This is not a live defect and must not be
"fixed" as one.

## Why it is filed anyway

The set is correct for a reason that has nothing to do with the set. It is
correct because two of its rightful members are unreachable — and the thing
making them unreachable (`compiler/cparser.inc`, the C entry stub) is exactly
the thing somebody will implement.

The four sites are `cparser.inc:1626`, `:1695`, `:1737`, `:1745`. The else they
fall into reads:

```pascal
if TargetArch <> TARGET_X86_64 then
  { Cross (aarch64): single GP-style save area ... one 8-byte-slot cross helper }
  helper := FindProc('__pxx_va_arg_cross')
```

The comment says **aarch64**; the condition says **everything that is not
x86-64**. Today those coincide. A new 32-bit target lands in the 8-byte-slot
path with a comment claiming it is aarch64 — silently, since varargs produce
wrong VALUES rather than a diagnostic, and the wrongness starts at the second
argument.

## The trigger, so this is findable at the moment it matters

**Whoever implements the C program entry stub for xtensa or wasm32 must add that
target to all four sets in the same commit.** Not afterwards: between the two
commits, C varargs on that target are silently wrong.

The cheap check is the same one that produced this ticket — compile a
`va_arg` C program for the new target and compare against gcc via
`tools/gcc_diff_probe.sh --target=<t>`.

## Not the fix

Do not paper over it by widening the set now. `TARGET_WASM32` in a list of
targets that cannot reach the code is a claim that will read as tested and is
not, and it removes the one thing that would make the real change necessary —
somebody noticing the target is missing. Leave the set honest and let the
trigger fire.

## Also worth doing when someone is in there

Reword the else's comment. `Cross (aarch64)` describes the only member it has
today, not the set it selects. Naming a branch after its sole occupant is what
made this take a measurement to see.

## 2026-09-04 — the xtensa half, discharged the way the ticket asked

`233e693bb` landed the xtensa C entry stub and the four set widenings together,
so the window this ticket was filed to prevent never opened.

**The requirement earned its keep, and it was still not enough.** With xtensa in
the 4-byte set, `printf("%llx", v)` still printed `55667788` for
`0x1122334455667788`, because two other things were wrong (see `7574a5f8d`).
Worth recording because the natural reading of "fix the set in the same commit"
is that the set IS the fix — it is the precondition. Anyone landing the wasm32
half should plan to run a `%lld` probe against the oracle, not just grep that
the target appears in four lists.

`wasm32` remains outside the set. The trigger is unchanged and the same commit
rule applies.

# 2026-09-05 (frankC, Track C): the trigger is now executable, and the set is untouched

`tools/c_va_arg_every_target.sh`, wired into `test-core`. **Nothing was widened**
— this is deliberately NOT the fix this ticket forbids. wasm32 is still outside
the four sets, still cannot compile a C program, and the completeness claim is
still unmeasurable for it. What changed is that the trigger no longer depends
on somebody reading a comment.

Per target: if it BUILDS, the three `va_arg` values must equal gcc's exactly;
if it REFUSES, the refusal must name the C entry stub. **The second arm is the
one that matters.** Without it a C frontend broken for every cross target turns
the whole check green — every row "refuses", and refusing reads as a pass.
That is the same structure as this ticket: a set that looks complete because
the members that would falsify it cannot run.

## The control that proves it is a guard

Ablation, from the exact population: `TARGET_RISCV32` removed from all four
sets, rebuilt, and riscv32 printed

```
1122334455667788 42 0.00      gcc: 1122334455667788 42 2.50
```

The silent-wrong-values defect this ticket describes, reproduced and caught.
Restored, green again. Four further controls — a non-entry-stub refusal, an
empty oracle, the built floor, the examined floor — each made to fail and each
did.

**The first attempt at those four proved nothing and looked fine.** I ran the
modified copies out of a temp directory; the script derives its root from
`dirname $0`, so every one died at the oracle step without reaching the arm
under test. Re-run from the repo root, they fire.

## Why the subject is shaped the way it is

`%llx`, then an int, then a double, in one call. A 64-bit argument read at the
wrong slot width prints the wrong half; the int after it shifts if the first
argument's size was misread; the double exercises the FP region on the two-bank
target. **One argument would pass on a target with a completely wrong slot
model.** The expected line is taken from gcc rather than written down, because
the claim under test is that the answer is target-independent.

This ticket's own 09-04 note is why it asserts VALUES rather than membership:
with xtensa in the set, `%llx` still printed `55667788` until `7574a5f8d`.

## The residual this ticket named is done

`cparser.inc:2093` still read `Cross (aarch64)`. The sibling at `:2171` was
reworded when xtensa landed and this one was missed — the same
fixed-one-arm-of-a-double-case shape the ticket is about. Both now name the SET
rather than its sole occupant. Comment only; binary sha `f519214f643f` before
and after.

## What stays unmeasurable, and who owns it

**wasm32.** Gated on
`bug-c-no-c-program-entry-stub-for-wasm32-so-no-c-program-can-target-it`
(`unfinished/`). Whoever lands that stub owns the widening, in the same commit —
and now also owns a row that will go RED the moment they do not, rather than a
sentence they may not read. **xtensa under the ESP profile** is also outside
this script's reach: it refuses on hosted linux, which this asserts, and
compiles C on the ESP profile, which this does not exercise.

## Line numbers above have drifted, and that is the point of not chasing them

This ticket's 08-31 body cites the four sites as `cparser.inc:1626`, `:1695`,
`:1737`, `:1745`. At 2026-09-05 they are `:1882`, `:2146`, `:2200`, `:2217`,
and the `Cross (aarch64)` else is `:2093` / `:2171`. The old numbers were
correct when written and now point at unrelated code — **a stale line number
does not error, it points somewhere**, which is exactly why the script that
landed today keys off VALUES and target names rather than positions. Left in
place as history; grep for the set literal instead.

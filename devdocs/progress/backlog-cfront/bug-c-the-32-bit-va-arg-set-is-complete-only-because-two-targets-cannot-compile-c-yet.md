---
slug: bug-c-the-32-bit-va-arg-set-is-complete-only-because-two-targets-cannot-compile-c-yet
track: C
prio: 35
type: bug
blocked-by: []
status: backlog
created: 2026-08-31
summary: "HALF DISCHARGED 2026-09-04, half still armed, and the ticket's own hard requirement was met. cparser.inc's four `TargetArch in [TARGET_I386, TARGET_ARM32, TARGET_RISCV32]' tests now read `[..., TARGET_XTENSA]': that widening landed in 233e693bb, THE SAME COMMIT as the xtensa C entry stub, which is what this ticket asked for. So xtensa can no longer silently take the 8-byte-slot else arm. Verified by running, not by reading: test/c_crtl_syscall_guarded_bodies.c and four vararg probes build and run under qemu-xtensa and match the gcc oracle. NOTE the widening alone was NOT sufficient -- with the set correct, 64-bit variadic arguments were still wrong for two further reasons (the direct-call ladder never classified a tail argument, and the caller's even-word pad disagreed with the walk's packed align=4), fixed in 7574a5f8d; membership in the 4-byte set is necessary and does not by itself make a target's varargs correct. wasm32 IS STILL ABSENT from the set and the trigger stays armed for it. THE GATE WAS MISNAMED AND IS CORRECTED HERE (2026-09-06, frankC): this said \"gated only by bug-c-no-c-program-entry-stub-for-wasm32-..., whoever lands that stub owes the same one-line widening in the same commit\". That stub LANDED (be2c87890) and the four sites are still unreachable, because the entry stub was never what gated them. The four sites are the CONSUMER side -- which helper reads a va_list. The gate is the PRODUCER side: the variadic prologue in ParseCSubroutine that spills registers into __va_save and anchors __va_overflow, which has SIX per-target arms (x86_64, aarch64, riscv32, i386, arm32, xtensa) and none for wasm32 -- that missing arm is the refusal. So the obligation now belongs to whoever adds a wasm32 PROLOGUE arm, not to anyone landing an entry stub. AND IT WAS NEVER ONE LINE: a new member also needs a vaRegSz (arm32 16, riscv32 32, xtensa 24, i386 0 -- wasm32 has no argument registers, so 0), and the cross32 helpers read a __va_save/__va_overflow pair that only a prologue arm creates. NOT WIDENED BLIND, deliberately: adding wasm32 to the four sets today would assert a va_list layout for a target that cannot produce one, unverifiable by any test that exists. THE TRIGGER IS NOW EXECUTABLE (2026-09-05, frankC): tools/c_va_arg_every_target.sh asserts, per target, that a build matches gcc exactly and that a REFUSAL names the C entry stub — the second arm being what stops a frontend broken for all cross targets from turning the check green. Proved a guard by ablation: TARGET_RISCV32 removed from the four sets made riscv32 print 0.00 where gcc says 2.50, which is the silent-wrong-values defect this ticket describes. NOTHING WAS WIDENED — the set is untouched and wasm32 stays unmeasurable by construction. The `Cross (aarch64)` comment residual at cparser.inc:2093 is also done -- the sibling at :2171 was reworded when xtensa landed and this one was missed. XTENSA IS NOW VERIFIED RATHER THAN ASSUMED (2026-09-05): the script gave every target its DEFAULT profile, so xtensa hit the ESP one, refused at the entry stub, and the row printed `outside this check by construction' -- false. With `--platform=posix' the same subject builds and qemu-xtensa RUNS it, matching gcc exactly, and all four set sites key on TargetArch alone so the profile cannot launder the result. 6 of 7 targets now assert VALUES; the built floor moved 5 -> 6. ONLY WASM32 IS STILL UNMEASURABLE, and it refuses at the entry stub on every profile it has. The ESP shipping path is covered too: `--emit-obj' must produce a Tensilica Xtensa REL object exporting app_main as a GLOBAL FUNC, which is the name the IDF links and calls."
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
sentence they may not read. **xtensa was ALSO listed here and that was wrong in both
directions** — corrected below.

## Line numbers above have drifted, and that is the point of not chasing them

This ticket's 08-31 body cites the four sites as `cparser.inc:1626`, `:1695`,
`:1737`, `:1745`. At 2026-09-05 they are `:1882`, `:2146`, `:2200`, `:2217`,
and the `Cross (aarch64)` else is `:2093` / `:2171`. The old numbers were
correct when written and now point at unrelated code — **a stale line number
does not error, it points somewhere**, which is exactly why the script that
landed today keys off VALUES and target names rather than positions. Left in
place as history; grep for the set literal instead.

# 2026-09-05 (frankC, second pass): xtensa was never out of reach, and I had the profiles backwards

The section above said xtensa *"refuses on hosted linux ... and compiles C on
the ESP profile"*. **Both halves are the wrong way round.** Measured at
`026c85149032`:

```
--target=xtensa                      refuses at the entry stub (the ESP default profile)
--target=xtensa --platform=posix     BUILDS, and qemu-xtensa RUNS it
                                     1122334455667788 42 2.50   == gcc, exactly
```

The script invoked every target with no `--platform`, so xtensa met its DEFAULT
profile — the ESP one, which has no standalone entry stub **by design** — and
printed `outside this check by construction`. **The refusal was real and the
conclusion drawn from it was false.** A target is only out of reach after the
profiles it actually has have been tried, and nobody had tried them.

This is the same shape as the ticket itself, one level up. The ticket is about a
set that looks complete because the members that would falsify it cannot run;
this was a row that looked out of reach because the one invocation tried could
not run. **An absence belonging to the instrument, read as an absence in the
world** — and I wrote the sentence claiming it the day before.

**The profile cannot launder the measurement**, which is the part that makes
this a verification rather than a coincidence: all four `TargetArch in [...]`
sites key on `TargetArch` **alone** and consult no platform or profile, so
`--platform=posix` exercises byte-for-byte the same va_arg lowering an ESP build
does. It changes the entry stub and the runtime, not the slot widths. **So
xtensa's membership in the 4-byte set is now asserted by running, not assumed
from a refusal.**

`built` floor raised **5 -> 6**. Lowering it again to re-admit a silent xtensa
refusal is the regression that number now exists to catch.

## wasm32 is genuinely out of reach, checked the same way rather than inherited

`--target=wasm32` and `--target=wasm32 --platform=posix` both refuse at the C
entry stub. (`--platform=bare` is **not an option at all** — the compiler
answers `unknown option`, so an earlier reading of "bare refuses" was the
compiler rejecting my flag, not the program. Checked, because a refusal whose
message I had not read is the thing this whole ticket is about.) The trigger
stays armed for wasm32 and nothing was widened.

## The ESP shipping path is now covered — frankS's residual, closed

frankS (`2beb2abec`): the standalone ELF is not how C reaches an ESP32.
`--emit-obj` is — the IDF links our object and calls `app_main` — and **that
path needs no entry stub, so the guard this script asserts never runs on it.**
Nothing in the suite would have noticed it regressing.

The new row asserts the **contract**, not the exit status: a real *Tensilica
Xtensa* relocatable object exporting `app_main` as a **GLOBAL FUNC**. `exit 0`
alone would pass on an empty file, and a `LOCAL` app_main is a build the IDF
cannot use. Its subject is stdarg-only and deliberately **not** the main one:
`c_va_arg_every_target.c` includes `<stdio.h>`, and printf drags in a crtl that
does not link on this path yet (`PXXMemZero not found`), so reusing it would
make the row red for a true statement about the wrong thing — and someone would
delete it.

## Controls, from the repo root this time

Four, each made to fail, each failing with **its own arm's message** rather than
a generic one:

| sabotage | fired |
| --- | --- |
| xtensa's `--platform=posix` removed | the built floor, `only 5 target(s)` |
| expected symbol `app_main` -> a name not exported | the GLOBAL FUNC contract |
| the emit-obj build retargeted to **x86_64** | the Machine check, printing `Advanced Micro Devices X86-64` |
| the emit-obj subject swapped to `$SRC` | the emit-obj build arm |

The third is the one worth keeping: it is a **real object from the wrong
target**, not a corrupted file, so it is drawn from the population the assertion
is about.

## 2026-09-06 (frankC): the wasm32 obligation was attached to the wrong event

`be2c87890` landed the wasm32 C entry stub. This ticket said the trigger was
*"gated only by"* that stub and that whoever landed it *"owes the same one-line
widening in the same commit"*. I landed it and did neither, and on measuring,
neither was the right discharge.

**The entry stub was never the gate.** The four sites choose which helper READS
a `va_list`. What refuses on wasm32 is the other half — the variadic prologue in
`ParseCSubroutine`, which spills the argument registers into `__va_save` and
anchors `__va_overflow`:

| | |
| --- | --- |
| prologue arms | `TARGET_X86_64`, `TARGET_AARCH64`, `TARGET_RISCV32`, `TARGET_I386`, `TARGET_ARM32`, `TARGET_XTENSA` |
| missing | **wasm32 — and that absence IS the refusal** |

So landing the entry stub changed nothing about reachability, and the same
refusal appears at the same place. **A C-capable target is not the trigger
condition; a target with a variadic prologue is.** The obligation belongs to
whoever adds the wasm32 prologue arm.

**And it was never one line.** A new member of the four sets also needs a
`vaRegSz` — the register-save-area size, `16` on arm32, `32` on riscv32, `24` on
xtensa, `0` on i386 — and the `cross32` helpers read a `__va_save` /
`__va_overflow` pair that only a prologue arm creates. `ir_codegen_wasm32.inc`
mentions none of `__va_save`, `__va_overflow`, `__pxx_va_arg_cross32` or
`__pxx_va_start_impl32`. Three things, not one.

**Not widened blind.** wasm32 is 32-bit with no argument registers, so `cross32`
with `vaRegSz = 0` — i386's shape — is the likely answer. It is not a measured
one: no test can reach those sites on wasm32, so adding the target would assert
a va_list layout for a target that cannot produce one, and would read afterwards
as a verified decision. That is the shape this ticket exists to prevent, pointed
the other way.

### What a future reader should do instead

Add the prologue arm and the four sites **together**, and let
`tools/c_va_arg_every_target.sh` grade it: wasm32 is in its `TARGETS` list, and
the moment it stops refusing at a named wall the script demands the same output
gcc gives.

**UPDATED 2026-09-06 (frankC): wall A is done and this section's advice has
inverted.** What stood here said the script stops at the ENVIRON wall, upstream
of the prologue, so it could not grade a wasm32 prologue arm until wall A
landed. Wall A landed (`63d077feb`), and the script now stops at **va_arg
itself, by name** — its admitted set is `{entry stub, va_arg-by-name}` and the
environ spelling was deleted, since no target can produce it any more.

So the script **is** the grader now, with one trap in front of it:

**A wasm32 prologue arm alone will make this script FAIL, not pass — and the
failure will be correct.** Hosted C on wasm32 has a third wall nobody could see
until A came out: `lib/crtl/src/stdio.c` hits `wasm: too many params+locals`
(`wasmenc.inc:87`, `MAX_WASM_BODY_VARS = 288`). This subject needs `printf`, so
it pulls stdio, so it will refuse there — and `too many params+locals` is not
in the admitted set, which is exactly the "this check silently stopped covering
the target" branch doing its job. Whoever adds the prologue must land the bound
too, or expect that failure and read it correctly.

### The freestanding subject is no longer a nice-to-have — it is the unblock

The old text called it "worth doing when someone starts wall A rather than
speculatively now". Wall A is done, so: **do it.** A subject that exercises
`va_arg` and reports through an EXIT CODE instead of `printf` needs no libc
headers, so it clears walls A, B and C in one move and lets the wasm32 prologue
be implemented and graded **without touching the crtl or the locals bound at
all.** That decoupling is the whole value and it was not obvious from here this
morning: the three crtl walls are in front of `printf`, and they are not in
front of `va_arg`.

`tools/c_wasm32_entry.sh` already runs freestanding C on wasm32 and compares
exit codes, so the mechanism exists and the work is a second subject, not a new
harness. Note the constraint that shapes it: the exit code is one byte, so the
`0x1122334455667788` argument this ticket's printf subject uses has to become
several narrow assertions folded into one number, and each must be NONZERO for
the reason written at the top of that script.
### The general form, which is why this is written up rather than just fixed

**A residual filed as an obligation on a FUTURE commit has no reader when that
commit arrives**, because the person landing it is reading their own ticket, not
the one pointing at them. It survived here only because a third party was
holding both tickets in mind. The durable version of *"whoever does X owes Y"*
is a check that goes red, or an edge on the ticket that X closes — never a
sentence in the body of a ticket X's author has no reason to open.

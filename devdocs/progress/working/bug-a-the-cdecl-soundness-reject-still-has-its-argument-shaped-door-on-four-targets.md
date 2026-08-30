---
track: A
prio: 50
type: bug
status: working
found: 2026-08-30
found-by: claude-A
owner: claude-A
---

# The cdecl soundness reject still has its argument-shaped door on i386/arm32/aarch64/riscv32

`bug-a-a-cdecl-procaddr-passed-as-an-argument-escapes-the-sysv-soundness-reject`
closed the **x86-64** half of this, by making the binding genuinely sound there
(`feature-cdecl-bodied-sysv-prologue`) rather than by fixing the guard. The guard
itself was never made shape-complete, and on the four targets that still need it
the door is exactly as open as it was.

Measured on aarch64 at slice 1, `82c135761`+slice-1:

| shape | aarch64 |
| --- | --- |
| `p := @MyCb; p(2.5, 7)` | refused: `... not C-callable yet` |
| `Take(@MyCb)` (argument) | compiles clean, prints **0** (want 9) |

Same source, same line numbers, one refused and one silently wrong.

## Why it was not fixed with the x86-64 half

The reject is keyed on `AN_ASSIGN` whose RHS is `AN_PROCADDR`. Making it
shape-complete means moving the check to wherever an `AN_PROCADDR` is coerced
INTO a location of `cdecl` proc type — and that is more than one more shape:

- a call argument bound to a `cdecl` proc-type formal (the measured hole)
- a record field or array element store
- a function `Result` of proc type
- a `const`/initialised variable declaration

Enumerating shapes is what produced this bug in the first place. The fix that
actually closes it is a single coercion chokepoint that both the assignment path
and every other path funnel through, which is a design question and not a
condition edit. `devdocs/dev/normalise-dont-special-case.md` is the relevant
doctrine: the second path is the one that stays broken, and there are currently
five.

## The other fix, which may be the better one

Give the four targets a real C-convention prologue arm, the way x86-64 now has
one (`EmitParamSpillsForTarget`'s `ProcCdecl` arm). Then the reject is obsolete
everywhere and gets deleted rather than repaired, and no shape enumeration is
needed at all. AAPCS64 and AAPCS32 both count integer and FP registers
independently, so the shape of the x86-64 arm carries over; riscv32's ILP32D
does too.

**This is the root-cause option and it closes the ticket by deletion.** Measure
tickets-closed-per-change, not lines touched: repairing the guard leaves the
underlying inability in place on four targets forever, and a repaired guard is
still a guard someone must keep shape-complete.

## Gate

On each of i386/arm32/aarch64/riscv32, under qemu: `Take(@MyCb)` with a
by-value float param and with >6 integer params either produces the correct
value, or is refused — never a wrong value. The x86-64 rows of
`test/test_cdecl_bodied_sysv.pas` become cross-target rows if the prologue
option is taken.


---

# PROGRESS (2026-08-30)

| target | arm | left the reject | notes |
| --- | --- | --- | --- |
| x86-64 | done | done | `feature-cdecl-bodied-sysv-prologue` |
| aarch64 | done | done | AAPCS64, independent x0..x7 / d0..d7 banks |
| arm32 | done | done | AAPCS soft-float; **half-joined**, see below |
| i386 | — | — | fails 3 of 8 narrow checks today |
| riscv32 | — | — | passes all 8 narrow checks today, which proves nothing |

**arm32 half-joins.** Its arm is correct for every signature it accepts and it
refuses any argument block over 4 core registers, because stack arguments are
unimplemented on both sides of the call there —
`bug-a-arm32-cdecl-has-no-aapcs-stack-argument-area`. Ordinary Pascal such as
five integer params is in the refused set. Saying "arm32 is done" without that
sentence would be false.

## The slicing is also the census, and that is why it is per-target

Sliced per target for bisectability. It turned out to be the only reliable way
to FIND the instances, which is a stronger argument and the one that should
survive the next person who wants to do all four at once.

**Each target diverged by a different mechanism, and each needed a
discriminating case built from its own ABI:**

- x86-64 / aarch64 — independent integer and float register banks. Discriminated
  by a MIXED signature: `f(i1,d1,i2,d2,i3,d3)`.
- arm32 — armel is SOFT-FLOAT and has no float bank at all. The mixed case is
  meaningless there. It diverges on 8-byte ALIGNMENT: `f(a: Integer; b: Double)`
  must skip r1 and land the double in r2:r3. Measured 7, want 9.

The other targets' discriminating case ALREADY PASSED on arm32 —
`f(a: Double; b: Integer)` gave the right answer, because soft-float coincides
with positional when the double is first. **A correct test pointed at the wrong
ABI reports a false green**, and reusing it would have shipped an arm nothing
tested. riscv32 passing all 8 narrow checks today is that same reading and must
be treated as mute, not clean.

## One predicate, four targets, four symptoms, and a census that cannot see it

"A by-ref parameter is a POINTER and classifies as one" is implemented
independently per backend, and was wrong in every one reached so far:

| target | symptom |
| --- | --- |
| x86-64 | pointer passed in xmm — segfault |
| aarch64 | pointer in the FP bank — segfault |
| arm32 | sized 8 bytes and 8-aligned instead of one word — block desync, segfault |

**A grep census does not find these.** `TypeIsFloat(Procs[` reports arm32 clean:
arm32 spells the rule as `tk = tyDouble` / `tk = tyExtended` against a local,
with no `TypeIsFloat` call near it. arm32 was fixed only because the alignment
work required reading that file line by line.

The count "4 sites across 4 backends" is *self-consistent* and still wrong — the
denominator came from the same grep. **An arithmetic cross-check only works when
the denominator comes from OUTSIDE the instrument** (`ls compiler/ir_codegen*.inc`
gives 7). Treat any grep count of this predicate as a lower bound.

So: **read i386's and riscv32's classification line by line; do not grep for it.**
The per-target slicing forces exactly that, which is why the remaining two will
surface their own instances regardless of who is paying attention.

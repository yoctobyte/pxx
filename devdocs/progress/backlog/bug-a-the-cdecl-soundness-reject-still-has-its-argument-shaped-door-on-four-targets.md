---
track: A
prio: 50
type: bug
status: open
found: 2026-08-30
found-by: claude-A
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

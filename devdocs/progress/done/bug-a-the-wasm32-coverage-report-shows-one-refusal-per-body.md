---
prio: 45
track: A
type: bug
status: done
summary: "FIXED (52d134518). The report kept ONE refusal per body and discarded the rest; it now keeps every DISTINCT reason, prints the further ones as `and also - <reason>`, and carries a gap count beside the body count. THE TICKET'S TWO PROPOSED SHAPES WERE NEARLY VACUOUS AND THE REPORT NOW SAYS SO: both assume a body's later refusals are reached, and the latch short-circuits ~40 guarded sites, so they usually are not. Measured over 300 sources: 14 programs have a broken body and 5 of those 14 have a body with a second distinct gap. The header therefore says the number is a FLOOR. A true census needs the walk to continue past a refusal, which is a codegen-robustness change and is not done here."
---

# The wasm32 coverage report shows one refusal per body and hides the others

`WasmUnsupported` records a refusal for the body being lowered, and the report
at the end prints one line per unlowered body:

```
wasm32: 128 of 129 bodies lowered; 1 emitted as `unreachable` (op coverage is incomplete):
    main$0 — string operand of type QWord
```

A program's whole main body is ONE entry. Everything a `main$0` needs that this
backend lacks collapses into whichever refusal happened first, and the rest are
invisible until that one is fixed — at which point the next appears and the
body is still red.

## What it cost, measured

`test_cross_sets`, `test_frozen_string_cross_b305` and
`test_static_string_literal` were excluded from `test-wasm32` with the note
`rc=134 trap via SetLength`, and a ticket recorded them as proof that the
SetLength gap "is not a corner case reached only by a probe". Measured
2026-09-03 with the `-101` arm both absent and present:

| test | without the arm | with the arm |
| --- | --- | --- |
| test_cross_sets | `value IR op 33` | `value IR op 33` |
| test_static_string_literal | `string operand of type QWord` | `string operand of type QWord` |
| test_frozen_string_cross_b305 | `value of type Pointer assigned to a managed string` | green |

Two of the three were never blocked by SetLength at all. They shared an EXIT
CODE — every unlowered body traps with rc=134 — and the report gave each one a
single cause that was true of the first gap it hit. The third turned green
through an unrelated fix (the comparison one), not through SetLength.

## Why this is worth fixing rather than noting

The number in that line is the honest part and is read as the dishonest one.
`128 of 129 bodies lowered` says almost everything works; what it measures is
that one body of one program is red, and a body is not a unit of coverage — a
whole program's main is one. A gap census built from these lines undercounts by
however many refusals were shadowed, and there is no way to tell from the output
whether a body had one gap or nine.

Two candidate shapes: keep a LIST per body and print all of them, or keep the
first per DISTINCT reason so one body cannot report the same missing op twice.
Either makes the count a gap count. Neither changes codegen.

[[bug-a-wasm32-setlength-on-a-shortstring-traps]]
[[bug-a-wasm32-shortstring-comparison-is-wrong-at-every-length]]

## Resolved - 52d134518

Both of the shapes this ticket proposed assume a body's later refusals are
REACHED. **They mostly are not**: `WasmUnsupported` latches and about forty
sites guard on that latch, so a second reason only arrives down a path that
does not. Measured over 300 sources with the listing in place: 14 programs have
a broken body at all, and 5 of those 14 have a body with a second distinct gap
(`lib_base64` 3, `test_assign_compatible_types` 2, three others 1 each).

**The denominator is the finding.** The first version of this number was
"91 of 300 reached the report, 86 recorded one reason", taken with a probe that
printed UNCONDITIONALLY -- so 77 of that 91 had nothing broken and could not
have recorded a second reason. 5-in-91 reads as a rarity; 5-in-14 does not. The
zero was vacuous over most of the population it was counted over, and both
source comments were corrected rather than left.

The ticket's own case study gains its second cause:

```
before   main$0 - string operand of type QWord
after    main$0 - string operand of type QWord
             and also - `=` on strings
```

and `test_assign_compatible_types` reports one body with three, `IR op 43`
shadowing the `SetLength` and `FreeMem` builtins behind it -- the same
misattribution shape this ticket documents, still live at the time of the fix.

Gate row in `test-wasm32` asserts the SECOND reason's TEXT, not a count: a count
row passes on a body that refuses the same op twice, which is what the dedup
exists to prevent. Control run rather than argued -- stashed, rebuilt
(d5a7b5d3ce4d), the row fails and prints the single shadowed cause; restored,
rebuilt (eac2ad1a536b), it passes.

Left open deliberately: making the count a true census means letting the walk
continue past a refusal. The emitted bytes are discarded anyway, so that is
cheap in output terms and NOT cheap in robustness terms -- forty guards exist
because a refused lookup leaves state a later site would read. Anyone taking it
should expect to measure compiler crashes, not report quality.

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit c6b3b8204.

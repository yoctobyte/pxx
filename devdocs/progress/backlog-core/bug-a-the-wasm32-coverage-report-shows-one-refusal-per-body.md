---
prio: 45
track: A
type: bug
status: open
summary: "wasm32's coverage report keeps ONE refusal per procedure body and discards the rest, so a body with three unrelated gaps reports only the earliest. Three excluded suite tests were written up as `trap via SetLength` on that evidence and NONE of them was blocked by SetLength -- measured with the arm both absent and present, the diagnostic does not change. The `N of M bodies lowered` count is honest about BODIES and reads as a measure of GAPS, which it is not."
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

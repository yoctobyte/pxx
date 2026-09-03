---
prio: 70
track: A
type: bug
status: open
summary: "REGRESSION SINCE PIN v401: under -dPXX_SHORTSTRING on x86-64, `frozenVar = ansiVar` answers FALSE for equal contents. Correct in the DEFAULT mode, correct at the pin in both modes, and correct at HEAD on i386/arm32/aarch64/riscv32/xtensa/wasm32 in both modes -- so it is the host backend and the flag together. Comparing the same frozen variable to a LITERAL is correct, which is the row a repro writes."
---

# A frozen string compared to an AnsiString is FALSE under the flag on x86-64

```pascal
type TS = string[8];
var a: TS; m: AnsiString;
begin
  a := 'abcde'; m := 'abcde';
  WriteLn(a = m);        { x86-64 -dPXX_SHORTSTRING: FALSE.  Everything else: TRUE }
  WriteLn(a = 'abcde');  { TRUE everywhere — the row that hides it }
end.
```

Measured 2026-09-03.

| | default | -dPXX_SHORTSTRING |
| --- | --- | --- |
| pinned compiler (v401), x86-64 | TRUE | TRUE |
| HEAD x86-64 | TRUE | **FALSE** |
| HEAD i386/arm32/aarch64/riscv32/xtensa/wasm32 | TRUE | TRUE |

## Why this one matters more than its size

It is the CROSS-REPRESENTATION compare — one operand with an inline prefix, one
with a heap handle — and it is wrong only in the mode phase 4 makes the
default, on the backend everything is measured on. The default-mode row beside
it is green, so a suite that runs one mode certifies it, and the flag row that
would catch it is exactly the row nobody had until
`test/test_frozen_compare_operand_shapes.pas`. That file is wired for x86-64 in
the DEFAULT mode only, with this ticket named at the point the flag row was left
out; wire it when this lands.

Not bisected. It arrived with the frozen-comparison / frozen-argument work of
2026-09-02/03.

[[bug-a-i386-comparing-two-elements-of-an-array-of-frozen-strings-is-false]]
[[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]]

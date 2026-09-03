---
prio: 70
track: A
type: bug
status: done
summary: "Under -dPXX_SHORTSTRING on x86-64, `frozenVar = ansiVar` answers FALSE for equal contents. WRONG SINCE THE FEATURE LANDED, not a regression: bisected to eadf214725a, the commit that introduced the x86-64 byte prefix, so the cross-representation compare has never worked in the narrow layout. Correct in the DEFAULT mode and correct at HEAD on every other target in both modes. Comparing the same frozen variable to a LITERAL is correct, which is the row a repro writes."
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

Measured 2026-09-03. Bisected: first bad commit **eadf214725a**, `feat(P): phase
2 — byte-prefix codegen, x86-64 complete and FPC-identical`. That commit
introduced the layout, so there is no earlier state in which this worked and no
change of anyone else's to look for.

| | default | -dPXX_SHORTSTRING |
| --- | --- | --- |
| HEAD x86-64 | TRUE | **FALSE** |
| HEAD i386/arm32/aarch64/riscv32/xtensa/wasm32 | TRUE | TRUE |

## THE PIN IS NOT A CONTROL FOR THIS, and reading it as one is how this was
## first filed as a regression

The pinned compiler (v401) answers TRUE under the flag — and it answers
`SizeOf(string[8])` = **16** while doing so. The pin predates the byte prefix,
so `-dPXX_SHORTSTRING` is a NO-OP in it: both pinned rows are the same
8-byte-prefix program and the flag row is the default row wearing a flag. A
control drawn from a population where the feature does not exist cannot fail,
and this one passed and certified a regression that never happened.

**The tell is in the control's own output.** `sizeof 16` in a mode that must
print 9 says the flag did nothing. Any pinned measurement of byte-prefix
behaviour has to print the size beside the answer, or it is measuring the other
layout.

## Why it matters more than one row

It is the CROSS-REPRESENTATION compare — one operand with an inline prefix, one
with a heap handle — wrong only in the mode phase 4 makes the DEFAULT, on the
backend everything else is measured on. The default-mode row beside it is green,
so a suite that runs one mode certifies it. The literal row is green too, which
is the comparand a repro naturally reaches for.

`test/test_frozen_compare_operand_shapes.pas` is wired for x86-64 in the DEFAULT
mode only, with this ticket named at the point the flag row was left out. Wire
it when this lands.

[[bug-a-i386-comparing-two-elements-of-an-array-of-frozen-strings-is-false]]
[[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]]

## Resolution (2026-09-03, frankB)

One line, and the file's own comments named the rule it broke twice over.
`ir_codegen.inc`'s equality block for a comparison with a managed operand did

```pascal
lhsTk := IntToTypeKind(IRTk[left]);
rhsTk := IntToTypeKind(IRTk[right]);
...
EmitAnsiStrCmpReg(op = tkEq, lhsTk, rhsTk);
```

while the ORDERING branch immediately below it and the frozen-only branch after
it both pass `IRStrTkOf`, each with a comment saying why: *the IR tags every
frozen string tyString generically*. So `EmitAnsiStrCmpReg` — which is correct
at either width and takes the width from the kind — was told 8 for a `string[N]`
whose prefix is one byte, and read the length byte plus seven characters as a
length. Every equality against a managed string failed; inequality mostly
passed, which is the same signature `EmitStrCmpReg` was fixed for earlier.

Three call sites of the same helper family, two converted and one not. Changed
to `IRStrTkOf` on both sides; the Char arms are unaffected because IRStrTkOf
returns tyChar for a Char node and tyAnsiString for a managed one, resolving
only the frozen kinds this block had wrong.

Verified in `test/test_frozen_compare_operand_shapes.pas` (`var_ans` row, with
its must-be-FALSE partner) on all seven targets in both modes, byte-identical to
FPC 3.2.2. Positive control: fix reverted, compiler rebuilt, the row returns to
FALSE.

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 2bd82200e.

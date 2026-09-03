---
type: bug
track: A
prio: 85
status: done
summary: FIXED `1c6234031`. Under -dPXX_SHORTSTRING on x86-64, `<` `>` `<=` `>=` on
  string[N] answered from the operand ADDRESSES, not the contents; `=` was correct
  because a wrong prefix width is applied symmetrically to both operands, so only
  ordering exposes it. Cause: EmitAnsiStrCmp3Reg, the SIBLING of the helper fixed
  earlier and never grepped for. Re-verified against the FPC oracle in both modes.
---

# String ordering comparison ignores content on x86-64 under the byte-prefix mode

**Silent wrong answers, no crash.** Any sort, binary search, or ordered insert
over `string[N]` is wrong under the flag. `=` and `<>` are correct (fixed with
the field-compare work); only the ORDERING operators are affected.

## Repro

```pascal
program o2;
var a, b: string[10];
begin
  a := 'abc'; b := 'abd';
  WriteLn('abc vs abd : a<b=', a<b, ' a>b=', a>b, ' a=b=', a=b);
  a := 'abd'; b := 'abc';
  WriteLn('abd vs abc : a<b=', a<b, ' a>b=', a>b, ' a=b=', a=b);
  a := 'zzz'; b := 'aaa';
  WriteLn('zzz vs aaa : a<b=', a<b, ' a>b=', a>b, ' a=b=', a=b);
end.
```

Measured at `45f6639f5`, compiler sha `a43276f1ce47`, exit 0 both modes.

| row | default | `-dPXX_SHORTSTRING` (x86-64) |
| --- | --- | --- |
| `abc` vs `abd` | `a<b=TRUE  a>b=FALSE` | **`a<b=FALSE a>b=TRUE`** |
| `abd` vs `abc` | `a<b=FALSE a>b=TRUE` | `a<b=FALSE a>b=TRUE` |
| `zzz` vs `aaa` | `a<b=FALSE a>b=TRUE` | `a<b=FALSE a>b=TRUE` |

**The answer is `a<b=FALSE, a>b=TRUE` for every input**, which is what comparing
two fixed stack slots as integers looks like — the same shape as the `CmpFusible`
address comparison, in the ordering path rather than the equality path.

**x86-64 only.** i386, arm32, aarch64 and riscv32 all answer `a<b=TRUE` for
`abc` vs `abd` under the flag.

## The guard trap — two of the three rows are RIGHT BY ACCIDENT

`abd` vs `abc` and `zzz` vs `aaa` both give the correct answer, because the
constant wrong answer happens to match. **A probe built from either of those
pairs passes with the bug fully present.** Only an ordering whose true answer is
`a<b=TRUE` distinguishes. Any content-blind comparison is right half the time by
construction — so an ordering probe needs BOTH directions, asserted, or it is not
a guard.

## RESOLVED — 1c6234031

Cause: EmitAnsiStrCmp3Reg, the sibling helper never grepped for after fixing EmitAnsiStrCmpReg.

Re-verified at 05f50f9ae with the repro in this ticket, unchanged, against the
FPC 3.2.2 oracle: exact match at default AND -dPXX_SHORTSTRING. Covered going
forward by test/test_frozen_field_and_deref_readers.pas, wired into all 12
expected blocks (4 native modes; x86-64, aarch64, arm32, riscv32, xtensa x 2
modes) — the 32-bit targets included, since this is a width class and x86-64 is
where width bugs hide.

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

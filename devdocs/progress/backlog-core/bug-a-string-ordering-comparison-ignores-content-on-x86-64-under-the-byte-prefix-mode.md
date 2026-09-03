---
type: bug
track: A
prio: 85
status: open
summary: Under -dPXX_SHORTSTRING on x86-64, `<` `>` `<=` `>=` on string[N] answer
  from the operand addresses, not the contents; `=` is correct. Silent, no crash.
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

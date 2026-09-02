---
type: bug
track: A
prio: 80
status: open
summary: Under -dPXX_SHORTSTRING, elements of a static array of string[N] read back
  corrupted, and Length() of a short element returns a garbage 64-bit value.
---

# An array of shortstrings is corrupt under the byte-prefix mode

**This blocks the phase-4 flip.** The flip turns `-dPXX_SHORTSTRING` on globally;
today that mode corrupts every static array of `string[N]`.

## Repro

```pascal
program arr;
var a: array[0..2] of string[8]; b: array[0..1] of string[4]; i: Integer;
begin
  a[0] := 'zero'; a[1] := 'one'; a[2] := 'two';
  b[0] := 'ab'; b[1] := 'cd';
  for i := 0 to 2 do WriteLn('a[',i,'] len=', Length(a[i]), ' val=[', a[i], ']');
  for i := 0 to 1 do WriteLn('b[',i,'] len=', Length(b[i]), ' val=[', b[i], ']');
  WriteLn('a[1]=one : ', a[1] = 'one');
end.
```

Measured at `ba90811d3`, compiler sha `a81084690bac`, x86-64, exit 0 in both modes:

| | default | `-dPXX_SHORTSTRING` |
| --- | --- | --- |
| `a[0]` | len=4 `[zero]` | len=4 **`[z  ]`** |
| `a[1]` | len=3 `[one]` | len=3 **`[o ]`** |
| `a[2]` | len=3 `[two]` | len=3 `[two]` |
| `b[0]` | len=2 `[ab]` | **len=2199023255554**, prints ~2KB of spaces |
| `b[1]` | len=2 `[cd]` | **len=72057594037927938**, prints empty |
| `a[1]='one'` | TRUE | **FALSE** |

## What the numbers say

**The length is right and the DATA is wrong for `string[8]`** — `a[0]` reports 4
and yields `z` plus padding, so the length byte is being found while the
character bytes are not. That is a stride/offset disagreement, not a prefix-width
misread on its own.

**For `string[4]` the length itself is garbage**: `2199023255554` = `0x20000000002`
and `72057594037927938` = `0x100000000000002`. Both end in `...02`, the real
length 2, with high bytes of the neighbouring element dragged in — a 64-bit load
where one byte was meant, at an element stride that no longer matches.
`b` has the smaller declared width, which is why it corrupts harder: the wrong
stride walks off the element sooner.

**A `Length()` of 7.2e16 is the dangerous part.** It is not a display defect —
anything that copies or iterates on that value overruns.

## Guard notes

`a[2]` reads CORRECTLY (`[two]`), so a probe that checked only the last element
would pass. `a[0]` reports the RIGHT length beside wrong data, so a probe
asserting only `Length` would pass too. Assert the VALUE, on the FIRST element,
at more than one declared width.

Found by the negative-control row of a widened repro, not by the repro's own
assertions.

## Not to be confused with

`feature-a-dynamic-array-of-frozen-strings` is a feature for DYNAMIC arrays.
This is a static array and a correctness bug.

## Narrowed 2026-09-02 22:2x (frankuser) — measurement only, files untouched

**Not an optimiser bug.** Identical at `-O0`, `-O1`, `-O2` and `-O3` on x86-64:
`a[0] len=4`, `b[0] len=2199023255554`, `a[1]='one'` FALSE at every level. So it
is **unlike `CmpFusible`** — the `-O0`-correct/`-O1+`-wrong tell does not apply
here, and the defect is in the layout/codegen arm rather than a predicate.

**Live control:** default mode at `-O2` gives `len=4 len=2 TRUE` on the same
harness, so these rows can produce the right answer.

**Cross-target, `-dPXX_SHORTSTRING`, default `-O`:**

| target | `a[0]` | `b[0]` len | `a[1]='one'` |
| --- | --- | --- | --- |
| x86-64 | len=4 | **2199023255554** | FALSE |
| aarch64 | len=4 | **2199023255554** | FALSE |
| i386 | len=4 | **2** *(looks correct)* | FALSE |
| arm32 | len=4 | **2** *(looks correct)* | FALSE |
| riscv32 | len=4 | **2** *(looks correct)* | FALSE |

**The 64/32 split is the most useful thing here, and it is a trap.** The three
32-bit targets report `b[0] len=2`, which is the CORRECT value — while the
comparison on the same element is still FALSE. `2199023255554` is `0x20000000002`:
**its low 32 bits are exactly 2.** So a length read from the wrong offset is
truncated on a 32-bit target into the right answer by accident.

**A `Length()` probe passes on i386, arm32 and riscv32 while the bug is fully
present** — the expected value collides with the failure value on precisely the
targets where a width bug is most likely to be looked for. Assert the VALUE
(`a[1] = 'one'`), which is FALSE on all five, never the length.

*Stated as measured. The register-width reading of `0x20000000002` is the
obvious explanation and is NOT measured — nobody has read the emitted load. It
is offered as where to point gdb first, not as a diagnosis; three theories died
on the field-compare tonight, each confirmed by source-reading first.*

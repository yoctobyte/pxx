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

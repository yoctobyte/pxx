---
type: bug
track: A
prio: 60
status: open
summary: "A record FIELD declared `array of string[N]` records a junk element
  capacity -- RecFieldStrCap answers 3 for `row: array of string[10]` and 1 for
  `m: array of array of string[10]` -- because the three field-declaration
  sites take fStrCap from LastTypeStrCap, which is not set when the element is
  a NAMED frozen alias. Elements then stride short and overwrite each other:
  silent wrong values on every target including x86-64, both modes. The
  identical declaration as a plain VARIABLE is correct."
---

# A frozen dynamic-array FIELD records a junk element capacity

```pascal
type TS10 = string[10];
     TR1 = record row: array of TS10; end;
     TR2 = record m: array of array of TS10; end;
var a: TR1; b: TR2; j: Integer;
begin
  SetLength(a.row, 3);
  for j := 0 to 2 do a.row[j] := 'r' + Chr(48+j) + 'yyyyyyy';
  Write('D1 '); for j := 0 to 2 do Write('<', a.row[j], '>'); WriteLn;
  SetLength(b.m, 1); SetLength(b.m[0], 3);
  for j := 0 to 2 do b.m[0][j] := 'r' + Chr(48+j) + 'yyyyyyy';
  Write('D2 '); for j := 0 to 2 do Write('<', b.m[0][j], '>'); WriteLn;
end.
```

```
D1 <r0y><r1y><r2y>                            { want <r0yyyyyyy> x3 }
D2 <r0yyyyyy<TAB>><r1yyyyyy<TAB>><r2yyyyyyy>  { the TAB is the next length byte }
```

Exit 0, no diagnostic. Measured at `19eafaaa86c1`, x86-64 default mode; the
byte-prefix mode is wrong differently and the VARIABLE spelling
(`var m: array of array of TS10`) is correct in both.

## The measurement, not a reading

`PXXDBG`-style probe inside `NodeDynBaseStrCap`'s AN_FIELD arm, on the program
above:

```
field=row rec=21 cap=3 tk=4 isarr=TRUE dyndepth=1
field=m   rec=22 cap=1 tk=4 isarr=TRUE dyndepth=2
```

`tk`, `isarr` and `dyndepth` are all right. **Only the capacity is wrong, and
it is not zero -- it is junk**, so every guard of the form `if cap > 0` reads it
as a real answer and no default fires. Both fields want 10.

The three field-declaration arms in `pasparser_decl.inc` (3380, 4193, 6050) all
spell:

```pascal
fStrCap := LastTypeStrCap;
if fStrCap <= 0 then fStrCap := DEFAULT_STR_CAP;
```

`LastTypeStrCap` is the stale channel `defs.inc` documents at length under
`AliasStrCap`: *"a USE of the alias is far from where `string[N]` was parsed, so
LastTypeStrCap is whatever the last unrelated declaration left behind."*
`AliasStrCap` exists for exactly this and is not consulted here.

## What this is NOT

**Not a missing carrier at the consumer.** A side table beside
`IRSetLenBaseRec` carrying the element capacity down to `SetLenDynElemSize` was
built, wired at all three `IR_SETLEN_DYN` lowering sites, and probed: the value
arrives, and it is the junk above. Consuming it makes the stride WRONGER than
today's pointer-width default (`FrozenStrSlotSize(tyString, 3)` = 11 rather than
8), so it was reverted rather than landed. The note left at
`SetLenDynElemSize`'s last arm records that. Fix the capacity at declaration
time and that arm becomes a three-line change.

**Not the same bug as the index-typing one it was found behind.** That was
`bug-a-a-field-rooted-array-of-array-of-string-n-indexes-as-a-char` (fixed):
the shape did not compile at all, which is why this was never measurable. The
depth-1 spelling `row: array of TS10` compiled all along and is wrong too, so
this one has been reachable and silent for longer.

## Where to look

- `pasparser_decl.inc:3380, 4193, 6050` — the three `fStrCap := LastTypeStrCap`.
- `defs.inc` `AliasStrCap` / `ArrTypeElemStrCap` — the carriers that DO hold N.
- `symtab.inc RecFieldStrCap` — the reader; correct, given a correct table.
- Fix all three sites in one edit: two of three is how this family recurs
  (`devdocs/dev/normalise-dont-special-case.md`).

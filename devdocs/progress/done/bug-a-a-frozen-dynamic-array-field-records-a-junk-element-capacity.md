---
type: bug
track: A
prio: 85
status: done
summary: "A dynamic-array FIELD whose element is a frozen `string[N]` gets no
  element capacity: the field parsers test `fIsDyn` first and return before the
  only arm that assigns `fStrCap`, so the field keeps whatever the PREVIOUS
  field left behind -- a neighbour's capacity (truncation) or 0, which the
  store path reads as no limit (overrun). Every spelling, record and class,
  both modes, every target. In the DEFAULT mode it SIGSEGVs: the allocation
  strides a pointer width while the store strides the real slot, and the crash
  lands at the NEXT allocation. FIXED -- capacity captured at declaration and
  carried to SetLenDynElemSize on IRSetLenBaseCap."
owner: frankA
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

**The reading of that measurement was wrong, and it is worth keeping wrong.**
It said: the three arms that spell `fStrCap := LastTypeStrCap` are reading a
stale channel, the one `defs.inc` documents under `AliasStrCap` as *"a USE of
the alias is far from where `string[N]` was parsed"*. Every word of that is
true about `LastTypeStrCap` in general and **none of it is what happened here**,
because a dynamic-array field never reaches any of those three arms at all. The
stale-channel story explained the junk so well that it stopped the search one
arm short of the arm that was never entered. A cause that fits is not a cause
that was observed: the discriminator was a two-line program, not a probe --
`record pad: string[17]; row: array of string[10] end` clamping at 17 says
"previous field", which no theory about alias resolution predicts.

## What this is NOT -- one half of which was wrong, and measured wrong

**"Not a missing carrier at the consumer" was the wrong half, and it was wrong
because the two halves were measured one at a time.** A side table carrying the
element capacity to `SetLenDynElemSize` was built, wired and probed, and it
delivered the junk above -- so it was reverted as making the stride *wronger*
than the pointer-width default. That reading was correct about the value and
wrong about the fix: the carrier is not an alternative to fixing the
declaration, it is **the other half of the same fix**, and neither half is
landable alone.

Landing the declaration half alone does not leave the old wrongness in place;
it makes it FATAL. The store's stride becomes truthful while the allocation's
stays at a pointer width, and 28 bytes go into an 8-byte element. Measured
2026-09-03, x86-64 default mode, `base c709788d39ad` vs the declaration fix
alone:

```pascal
R1 = record row: array of string[20]; end;
C1 = class  row: array of string[20]; end;
SetLength(a1.row, 1); a1.row[0] := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';  { prints fine }
c := C1.Create; SetLength(c.row, 1);                               { SIGSEGV }
```

base rc=0, declaration-fix-only rc=139 -- and the crash is two statements after
its cause. Store 2 characters instead of 26 and it survives; make the element
`Integer` and it survives. **The malloc bucket was the only thing standing
between two wrong strides and a crash, and fixing either half alone removes
it.** frankb-78 hit the mirror image on dyn2dvals (`e69e71ed2`): allocation 8
bytes/element, 3 elements asked 24 and the bucket returned 56, the index path
strided 18 and needed 54, which fit -- until prefix padding took the stride to
24 and 72 did not.

**Not the same bug as the index-typing one it was found behind.** That was
`bug-a-a-field-rooted-array-of-array-of-string-n-indexes-as-a-char` (fixed):
the shape did not compile at all, which is why this was never measurable. The
depth-1 spelling `row: array of TS10` compiled all along.

**Not "a NAMED frozen alias", which is what the summary used to say.** The
inline spelling `array of string[10]` is equally broken, and so is a named dyn
TYPE. The alias is not the discriminator; `fIsDyn` is.

## The cause, and the two faces of it

`ParseRecordFields` and its class twin both test `fIsDyn` FIRST. That arm
returns before the `(fTk = tyFixedString) or (fTk = tyShortString)` arm, which
is the ONE place `fStrCap` is ever assigned -- so a dynamic-array field keeps
the value the loop left there for the previous field.

Measured at cap 20 with a 26-character store, base vs fixed:

| shape | base | fixed |
| --- | --- | --- |
| `var v: array of TS` | 20 | 20 |
| record, inline dyn, alias element | 3 | 20 |
| record, inline dyn, inline element | 3 | 20 |
| record, named dyn type | 3 | 20 |
| record, FIXED array field | 20 | 20 |
| class, inline dyn | **26** | 20 |

The 3 is the leftover from the builtin prelude, which is why it is the same 3
in every program and reads like a real answer. The class row's 26 is the
LITERAL'S length, not a capacity: with nothing frozen in front of the field the
leftover is 0 and the store path reads 0 as "no limit". Put a neighbour in
front and the class face truncates like the record one -- `pad: string[17]`
gives 17, `pad: string[9]` gives 9. **An absent answer and a wrong one, out of
one hole.**

## The fix

- `pasparser_decl.inc` -- both field parsers, both dyn arms (inline `array of
  T` and named dyn type), capture the element capacity: `LastTypeStrCap` in the
  inline arm (correct there and only there -- `ParseTypeKind` has just run on
  the element) and `ArrTypeElemStrCap[fAi]` in the named-type arm.
- `defs.inc` / `ir.inc` -- new `IRSetLenBaseCap` node field, written beside
  `IRSetLenBaseRec` at the three non-symbol lowering sites (`RecFieldStrCap`
  for the AN_FIELD arm, `NodeDynBaseStrCap` for the nested-index and
  `IR_STORE_DYN` arms).
- `ir_codegen.inc` -- `SetLenDynElemSize` takes the node capacity and uses it
  where it used to demand `symIdx >= 0`. Its remaining kind-only arm is still
  reachable and still deliberate: a dyn array returned by a CALL has no
  capacity carrier at all.

Verified on x86-64, i386, arm32, aarch64 and riscv32, both modes, plus an
xtensa compile. `test/test_dyn_frozen_field_capacity.pas` is the regression,
and it is a positive control: on `c709788d39ad` it is red in both modes, in the
default one printing descriptor bytes out of the heap.
`test_string_n_container_strides` (all eight rows incl. `dyn2dvals`) stays green
on all five runnable targets in both modes.

## Ranking

Raised 60 -> 85, on my own measurement and at frankuser's request rather than
by its ask. It is a SIGSEGV in the DEFAULT mode -- the shipping build -- in a
shape that has always compiled, with no diagnostic; the flag-mode face is
silent truncation whose length depends on an unrelated neighbouring
declaration. That is the argument that took the i386 compare from 70 to 80.

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit aee455a16.

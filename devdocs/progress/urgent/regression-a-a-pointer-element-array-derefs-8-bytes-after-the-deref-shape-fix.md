---
slug: regression-a-a-pointer-element-array-derefs-8-bytes-after-the-deref-shape-fix
title: "`a[i]^` reads 8 bytes for a 4-byte element after 381fb9e37, in the PLAIN spelling"
track: A
prio: 70
type: regression
status: new
found: 2026-09-01
found-by: frankB
owner: ""
blocked-by: []
summary: "381fb9e37 (the p^[i] carriers) regressed `array of PInteger`: writing through `p^[i] := @nums[i]` and reading back `a[0]^` yields 0x0000000B_0000000A -- nums[1]<<32 | nums[0], an 8-BYTE read where the element is a 4-byte Integer. Bisected by building both sides: ok at 0f82c481c26b (pre-fix), WRONG at ffb4dadcf1f8 (post-fix). It is the PLAIN spelling, i.e. the one that always worked and the one every other row is measured against, so it is a ds_plain_* CONTROL row in test/derefshape: while it is red `make derefshape` aborts and reports NO row verdicts at all, which is correct behaviour and also means the check is currently useless as a gate for everyone. 381fb9e37 wired it into `make test`, so `make test` now aborts this check rather than passing it."
---

# `a[i]^` derefs 8 bytes for a 4-byte element (plain spelling)

## Measured, both sides built

| binary | commit | `ds_plain_ptrelem` |
| --- | --- | --- |
| `0f82c481c26b` | `381fb9e37^` | **ok** (`10 13`) |
| `ffb4dadcf1f8` | `381fb9e37`+ | **WRONG** (`47244640266 18490349605355533`) |

Not read off notes: `git checkout 381fb9e37^`, `make compiler/pascal26`, run,
then back to master and rebuild. `0f82c481c26b` is independently the binary
frankA reported as their pre-fix build, which is the second source that the
right thing was built.

## The value decodes, so this is not a mystery

`47244640266` = `0x0000000B_0000000A` = `nums[1] shl 32 or nums[0]` = 11 and 10
packed into one 64-bit quantity. **`a[0]^` performs an 8-byte read where the
element is a 4-byte `Integer`.** The pointee WIDTH is coming out 64-bit for a
`PInteger` element — depth's near neighbour, and the *"a symbol parks it one
level up"* hazard from `381fb9e37`'s own design note, landing on the read side.

## Repro

`test/derefshape/ds_plain_ptrelem.pas`, or:

```pascal
program r;
type TA = array of PInteger; TP = ^TA;
var a: TA; nums: array[0..3] of Integer; p: TP; i: Integer;
begin
  for i := 0 to 3 do nums[i] := 10 + i;
  SetLength(a, 4);
  p := @a;
  for i := 0 to 3 do p^[i] := @nums[i];
  WriteLn(a[0]^, ' ', a[3]^);      { expect: 10 13 }
end.
```

## Why it was not caught

`381fb9e37`'s own five-face harness has no row whose element is a POINTER, and
neither did the first 15 rows of `test/derefshape` — every element kind was a
scalar (`Double`, `AnsiString`). A wrong pointee width or a dropped level of
indirection is invisible when the element is a scalar, because the value read
back is the right number either way. The `ptrelem` kind was added in
`787d353f7` specifically for that class, after `15ec54d7a` had regressed the
same way (dropped DEPTH, right pointee) and been fixed in `bfb7b4c59`.

**So this is the second regression of that exact class**, and the first one
found by an instrument rather than by a user.

## Do not "fix" it by relaxing the control

The tempting repair is to drop `ds_plain_ptrelem` from the control set so the
matrix reports its other 19 rows again. That converts a guard that fired into a
guard that cannot, and the row is a control precisely because the plain spelling
is the reference every other row is compared against. Fix the width; leave the
row.

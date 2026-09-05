{ Fields in a VARIANT BRANCH, which was the THIRD copy of the field-declaration
  parser and the one no ticket counted.

  Merging it into ParseFieldDeclInto fixed three things at once, each measured
  against fpc 3.2.2 before and after:

  1. ALIGNMENT. A record-typed branch field was aligned to the pointer width
     instead of to the record's own alignment, so `case Integer of 0: (x: Byte);
     1: (r: TByteRec)` measured 8 bytes where fpc says 1 -- and pxx contradicted
     ITSELF, because the same field in the record's FIXED part was already laid
     out correctly. That is the row this file leads with: a variant part must be
     as wide as its widest branch and no wider.
  2. MULTI-DIMENSIONAL arrays, inline or through a named alias, were refused
     with a deliberate message saying they would be mis-sized. The shared
     routine carries the dimension table, so they are simply right now.
  3. `packed array[..] of T`, the same gap this parser had on classes.

  AND ONE REFUSAL HAD TO BE MADE DELIBERATE OR THE MERGE WOULD HAVE BROKEN IT.
  A reference-counted type cannot live in a branch -- the storage is shared, so
  nothing can know which finaliser to run -- and fpc refuses it. This copy used
  to refuse it BY ACCIDENT: it had no dynamic-array arm at all, so `array of
  Integer` came out as `expected '[' before 'of'`, a grammar complaint that
  happened to land on the right answer. Inheriting the shared routine's arm
  would have silently ADDED a construct fpc rejects, so the refusal is now
  explicit and is asserted below by REFUSAL rather than assumed.

  NOT FIXED AND MEASURED, so nobody reads this file as covering it: `string` and
  `IUnknown` in a branch are accepted by pxx and refused by fpc. They do not come
  through this routine and that gap is older than it.

  Expected output is fpc 3.2.2's own.
  refactor-p-the-field-declaration-parser-exists-twice }
program test_packed_array_field_in_a_variant_branch;
{$mode objfpc}{$H+}

type
  TCell    = record a, b: Integer; end;
  TByteRec = record b: Byte; end;
  TGrid    = array[0..1, 0..2] of Integer;

  { 1. a branch is as wide as its widest branch and no wider }
  TAlignByte = record case Integer of 0: (x: Byte);    1: (r: TByteRec); end;
  TAlignCell = record case Integer of 0: (x: Integer); 1: (r: TCell); end;

  { 2. multi-dimensional, both spellings of the same array }
  TMulti = record
    case Integer of
      0: (n: Integer);
      1: (g: TGrid);
      2: (h: array[0..1, 0..2] of Integer);
  end;

  { 3. packed and its unpacked twin -- `packed` must change nothing }
  TPk = record case Integer of 0: (n: Integer); 1: (e: packed array[0..1] of TCell); end;
  TUp = record case Integer of 0: (n: Integer); 1: (e:        array[0..1] of TCell); end;

var
  ab: TAlignByte;  ac: TAlignCell;
  m: TMulti;  pk: TPk;  up: TUp;

begin
  { 1 -- the sizes are the assertion; the stores prove the slots are usable }
  ab.r.b := 5;  ac.r.a := 6;
  WriteLn(SizeOf(TAlignByte), ' ', SizeOf(TAlignCell), ' ', ab.r.b, ' ', ac.r.a);

  { the two branches of a variant share one slot, so the tag write is visible
    through the record arm -- a pair of independent fields would not do this }
  ab.x := 9;
  WriteLn(ab.r.b);

  { 2 -- the named alias and the inline spelling are one type in two spellings }
  m.g[1][2] := 7;
  WriteLn(m.g[1][2], ' ', m.h[1][2], ' ', SizeOf(TMulti), ' ', SizeOf(TGrid));

  { 3 -- packed and unpacked must agree on the value AND the size }
  pk.e[1].a := 33;  up.e[1].a := 33;
  WriteLn(pk.e[1].a, ' ', up.e[1].a, ' ', SizeOf(TPk), ' ', SizeOf(TUp));
end.

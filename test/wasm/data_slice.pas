{ SPDX-License-Identifier: MPL-2.0 }
{ Data-segment slice oracle. Same two-role shape as the other slices: with
  WASM_NOMAIN it is a library of exported functions for the wasm side, without
  it a program whose printed output is the native answer.

  What this phase adds is a REGION, not an opcode, so the failures it can have
  are addressing failures rather than validation failures:

    Lookup     a typed const array — a global whose STORAGE is in Data[], so
               its symbol carries DATA_SYM_BIAS and its address is the $data
               global plus an offset, not a constant. This is the whole reason
               the phase exists; a backend that forgets the bias computes an
               address near 0x20000400, past the end of linear memory.
    Wide, RealCmp element widths other than 4, so the index scaling is visible.
    Table2     a 2-D typed const: row stride times column, both from the blob.
    Pair       a typed const RECORD, where the field offset is added to a base
               that is itself a sum.
    Mixed      a BSS global and a Data[] global in one expression — the two
               addressing paths in a single instruction stream, which is where
               a base confusion shows up as a plausible wrong number rather
               than a trap.
    Sum        a loop over the blob: the address is recomputed per iteration,
               so an off-by-one in the base is a wrong total, not a crash. }
program DataSlice;

type
  TPair = record A, B: Integer; end;

const
  Lut: array[0..7] of Integer = (3, 1, 4, 1, 5, 9, 2, 6);
  WideLut: array[0..3] of Int64 = (10000000000, -2, 3, 4000000000);
  RealLut: array[0..3] of Double = (1.5, 2.25, -0.5, 100.0);
  Grid: array[0..2, 0..3] of Integer = ((1, 2, 3, 4), (5, 6, 7, 8), (9, 10, 11, 12));
  Duo: TPair = (A: 11; B: 22);

var
  Counter: Integer;

function Lookup(i: Integer): Integer;
begin Lookup := Lut[i]; end;

function Wide(i: Integer): Int64;
begin Wide := WideLut[i]; end;

{ A comparison rather than Trunc: float->int is a builtin that needs the heap
  (Phase 6), and what this is here to prove is that an f64 was loaded from the
  right address, which a comparison shows exactly as well. }
function RealCmp(i: Integer; t: Integer): Integer;
begin
  if RealLut[i] > t then RealCmp := 1
  else if RealLut[i] < t then RealCmp := -1
  else RealCmp := 0;
end;

function Table2(r, c: Integer): Integer;
begin Table2 := Grid[r, c]; end;

function PairA: Integer;
begin PairA := Duo.A; end;

function PairB: Integer;
begin PairB := Duo.B; end;

function Mixed(n: Integer): Integer;
begin
  Counter := n * 100;
  Mixed := Counter + Lut[n];
end;

function Sum: Integer;
var i, t: Integer;
begin
  t := 0;
  for i := 0 to 7 do t := t + Lut[i];
  Sum := t;
end;

function SumWide: Int64;
var i: Integer; t: Int64;
begin
  t := 0;
  for i := 0 to 3 do t := t + WideLut[i];
  SumWide := t;
end;

{$ifndef WASM_NOMAIN}
begin
  writeln(Lookup(0));
  writeln(Lookup(5));
  writeln(Lookup(7));
  writeln(Wide(0));
  writeln(Wide(1));
  writeln(Wide(3));
  writeln(RealCmp(0, 1));
  writeln(RealCmp(1, 3));
  writeln(RealCmp(2, 0));
  writeln(RealCmp(3, 100));
  writeln(Table2(0, 0));
  writeln(Table2(1, 2));
  writeln(Table2(2, 3));
  writeln(PairA);
  writeln(PairB);
  writeln(Mixed(3));
  writeln(Sum);
  writeln(SumWide);
end.
{$else}
begin
end.
{$endif}

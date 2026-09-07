program test_mgmt_operators_multidim_array;
{ A MULTI-DIMENSIONAL fixed array of a record with management operators, as a
  SYMBOL and as a FIELD. Storage is flat row-major and the recorded extent is
  the FLAT element count, so one loop walks any dimensionality -- what changes
  with the dimension count is not the loop, it is the INDEX SPACE.

  EVERY LOW BOUND HERE IS NON-ZERO AND THAT IS THE POINT. A 0-based version of
  this file is a test that cannot fail. Measured 2026-09-07 with the dimension
  guard removed: `array[0..1, 0..2] of TFoo` walked flat is CORRECT and matches
  fpc 3.2.2 element for element, because the flat index and the dimensional
  index coincide when the origin is zero. `array[1..2, 5..7]` is what separates
  them -- walked from its own low bound it printed `001234` against fpc's
  `012345` and finalized a sixth element holding the neighbouring `k` field, a
  write outside the array with one element never initialized. Anything asserting
  about multi-dimensional indexing on a 0-based array is measuring nothing.

  THE INDEX SPACE RULE THIS FILE PINS. A synthesised single-subscript AN_INDEX
  over a 1-D array is read in SOURCE space (the low bound is subtracted, so
  `array[2..3]` is walked 2..3 -- test_mgmt_operators_array and
  test_mgmt_operators_array_field hold that half); over an N-D array nothing is
  subtracted and the same node is read in FLAT space, so it is walked
  0..count-1. Both halves must stay covered or a fix to one silently breaks the
  other.

  Four shapes, chosen so no two share a mechanism:
    sym   a 2-D array SYMBOL             -- symbol table, Syms[].ConstVal path
    fld   a 2-D array FIELD beside a scalar -- field table, UFldArrDimLo path,
                                              and `k` is the neighbour a
                                              past-the-end write lands on
    fld3  a 3-D FIELD, all three lows non-zero -- the flat count is a product of
                                              three spans, not two
    nest  a 2-D FIELD whose ELEMENT holds its own 1-D array field -- the flat
                                              walk nested inside a flat walk

  .expected IS fpc 3.2.2's output, byte for byte. Every arm prints back the `n`
  that Initialize is the only writer of, because a declared invariant that never
  runs cannot fail a value check unless the value is read back.
  feature-pascal-management-operators-nested-and-array }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    n: Integer;
    class operator Initialize(var a: TFoo);
    class operator Finalize(var a: TFoo);
  end;
  T2Fld = record m: array[1..2, 5..7] of TFoo; k: Integer; end;
  T3Fld = record q: array[3..4, 1..2, 7..8] of TFoo; end;
  TInner = record r: array[2..3] of TFoo; end;
  TNest = record z: array[1..2, 4..5] of TInner; end;

var
  seq: Integer;

class operator TFoo.Initialize(var a: TFoo);
begin
  a.n := seq; writeln('init ', seq); seq := seq + 1;
end;

class operator TFoo.Finalize(var a: TFoo);
begin
  writeln('fin  ', a.n);
end;

procedure PSym;
var m: array[1..2, 5..7] of TFoo;
begin
  writeln('sym  ', m[1,5].n, m[1,6].n, m[1,7].n, m[2,5].n, m[2,6].n, m[2,7].n);
end;

procedure PFld;
var b: T2Fld;
begin
  b.k := 9;
  writeln('fld  ', b.m[1,5].n, b.m[1,6].n, b.m[1,7].n, b.m[2,5].n, b.m[2,6].n, b.m[2,7].n, ' ', b.k);
end;

procedure P3;
var c: T3Fld;
begin
  writeln('fld3 ', c.q[3,1,7].n, c.q[3,1,8].n, c.q[3,2,7].n, c.q[3,2,8].n,
                   c.q[4,1,7].n, c.q[4,1,8].n, c.q[4,2,7].n, c.q[4,2,8].n);
end;

procedure PNest;
var d: TNest;
begin
  writeln('nest ', d.z[1,4].r[2].n, d.z[1,4].r[3].n, d.z[1,5].r[2].n, d.z[1,5].r[3].n,
                   d.z[2,4].r[2].n, d.z[2,4].r[3].n, d.z[2,5].r[2].n, d.z[2,5].r[3].n);
end;

begin
  seq := 0;
  PSym;
  PFld;
  P3;
  PNest;
  writeln('done');
end.

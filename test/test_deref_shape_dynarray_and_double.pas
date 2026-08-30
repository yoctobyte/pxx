{ The two deref spellings test_deref_shape_through_arith_and_nonident_base.pas
  does not reach, added beside it rather than instead of it.

  That test pinned the fix in `72b4bd51a` (an index over a non-IDENT base, and
  pointer arithmetic) with the right controls — `^Integer` and `^Byte`
  arithmetic, where a wrong pointee moves the NUMBER. These are the two shapes
  its rows cannot cover, both found by measuring rather than by reading:

  d — a DYNAMIC two-dimensional index is a genuinely NESTED `AN_INDEX`, while a
      FIXED one is a SINGLE `AN_INDEX` whose subscript is a computed offset.
      Confirmed with `PXXDBG=a.ast`, not assumed — I had assumed the opposite.
      So `g[j][i]^` never exercises the nested-base arm and `dy[1][0]^` does,
      and only the fixed spelling was covered.

  e — pointer arithmetic yielding TWO levels, `(pa + i)^^`. Every arithmetic row
      in the sibling test derefs once, so the arm could carry the pointee and
      still drop the remaining depth without any row noticing.

  Rows f and c are controls and are the reason the gap survived: the fixed 2-D
  index and the plain double deref were correct throughout, which reads as
  "nested indexing and multi-level derefs are supported".

  Against `pinned` (992065f21f33) rows d and e each print a raw ADDRESS while f
  and c print the string; fpc 3.2.2 prints the string for all four. Checked in
  that direction on purpose — a test written after a fix that also passes on the
  broken binary is testing nothing. }
program test_deref_shape_dynarray_and_double;
{$mode objfpc}{$H+}
type
  PPC   = ^PChar;
  PPPC  = ^PPC;
  TRow  = array[0..1] of PPC;
  TGrid = array[0..1] of TRow;
  TDyn  = array of array of PPC;
var g: TGrid; dy: TDyn; q: PPC; pa: PPPC; s1: PChar; i, j: Integer;
begin
  s1 := 'alpha'; q := @s1; i := 0; j := 1;
  g[1][0] := q;
  SetLength(dy, 2); SetLength(dy[1], 2); dy[1][0] := q;
  pa := @g[1][0];
  WriteLn('f ', g[j][i]^);   { control: fixed 2-D — ONE flattened index }
  WriteLn('c ', pa^^);       { control: a plain double deref            }
  WriteLn('d ', dy[1][0]^);  { dynamic 2-D — a NESTED AN_INDEX          }
  WriteLn('e ', (pa + i)^^); { arithmetic yielding TWO levels           }
end.

program test_inline_ptr_cast_low_bound;
{$mode objfpc}{$H+}
{ `PLo(@lo)^[3]` where the pointee is `array[2..4] of Integer`.

  The pointer-alias cast's PRIVATE postfix loop asked DerefPtrArrayElem for the
  element KIND and never asked for the pointee's low BOUND, so the subscript was
  used raw: `PLo(@lo)^[3]` read element 3 of a 3-element array instead of
  element 1, and answered 0 where fpc 3.2.2 answers 99. Silent, no diagnostic.

  ONLY the INLINE cast was wrong. `p := @lo; p^[3]` was always correct, because
  a pointer VARIABLE goes through the SHARED loop in pasparser_lval.inc, which
  has folded the bound since bug-a-indexing-through-a-pointer-to-an-array-is-
  wrong-for-several-element-kinds. One construct, two walkers, and the private
  copy was missing what the shared one knew -- refactor-p-three-hand-rolled-
  postfix-loops, which predicts exactly this.

  `viaptrvar=` is therefore not redundant with `viacast=`: it is the row that
  says the two routes now AGREE, rather than that either one moved. `lo0=`
  holds the zero-bound case that hid this for as long as it existed, and `nd=`
  guards the N-D exclusion (BuildFlatNDIndex already subtracts every low bound,
  so folding twice would index i - 2*lo0).

  This test exists separately from test_cast_to_array_type.pas deliberately:
  that one reaches this path by delegation, so if the array cast is ever
  reimplemented, this row must still hold on its own spelling.
  bug-p-an-inline-pointer-alias-cast-loses-the-pointees-low-bound }
type
  TLo   = array[2..4] of Integer;  PLo = ^TLo;
  TZero = array[0..2] of Integer;  PZero = ^TZero;
  TNeg  = array[-2..0] of Integer; PNeg = ^TNeg;
  TND   = array[1..2, 1..2] of Integer; PND = ^TND;
var lo: TLo; z: TZero; ng: TNeg; nd: TND; p: PLo;

{ The call-RESULT postfix loop (ApplyCallResultPtrSuffix) is a FOURTH site that
  mints an AN_INDEX over a deref, and the three-site census missed it. Both
  spellings, because `GetP^` and `GetP()^` take different routes in. }
function GetP: PLo;
begin
  GetP := @lo;
end;

begin
  lo[2]:=88; lo[3]:=99; lo[4]:=111;
  z[0]:=10; z[1]:=20; z[2]:=30;
  ng[-2]:=7; ng[-1]:=8; ng[0]:=9;
  nd[1,1]:=41; nd[2,2]:=44;
  p := @lo;
  WriteLn('direct   =', lo[3]);
  WriteLn('viaptrvar=', p^[3]);
  WriteLn('viacast  =', PLo(@lo)^[3]);
  WriteLn('lastelem =', PLo(@lo)^[4]);
  WriteLn('lo0      =', PZero(@z)^[1]);
  WriteLn('neg      =', PNeg(@ng)^[-1]);
  WriteLn('nd       =', PND(@nd)^[2,2]);
  WriteLn('callres  =', GetP^[3]);
  WriteLn('callres2 =', GetP()^[3]);
  PLo(@lo)^[2] := 55;
  WriteLn('wrote    =', lo[2]);
  GetP^[4] := 66;
  WriteLn('callwrote=', lo[4]);
end.

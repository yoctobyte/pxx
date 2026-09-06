{ An open-array LITERAL passed through a procedural-type call kept its length.

  It did not. `c := @Show; c([7,8,9])` answered Length(A) = 263845145632, and
  the same callback typed `of object` answered 0, where fpc 3.2.2 says 3 for
  both. The length was not lost in marshalling -- it was never computed, because
  `[7,8,9]` was parsed as a SET LITERAL. `PXXDBG=a.ir` showed `set_lit tk=21`
  and ONE argument where the direct call emits an array temp plus `const_int 3`
  and two. The wrong value said so itself: A[0] came back 896, which is the set
  bitmask for {7,8,9}.

  WHY EVERY ROW HERE IS A MATRIX CELL AND NOT A SPELLING. Four of the six
  combinations below were already correct -- direct/literal, direct/variable,
  indirect/variable, and `of object`/variable -- so a test that probed any of
  them, or that only checked "does it compile", passed throughout. The two that
  failed are the two nobody reaches for first, and one of them answered 0, which
  is a LEGAL length: a caller looping `to Length(A)-1` does nothing, quietly,
  and a probe passing `[]` gets the right answer for the wrong reason. Hence
  both a non-empty literal AND an element read on every row; a length alone
  cannot tell a correct vector from a set reinterpreted as one.

  The `of object` rows matter separately: that is the form FPC's fcl-passrc
  declares at pscanner.pp:575, and it is a different builder from the plain
  procedural type.
  bug-p-an-open-array-literal-loses-its-length-through-a-procedural-type-call }
{$mode objfpc}
program test_an_open_array_literal_through_a_procedural_type;
type
  TOpenCb = procedure(const A: array of Integer);
  TObjCb  = procedure(const A: array of Integer) of object;
  TSink = class
    procedure M(const A: array of Integer);
  end;

procedure TSink.M(const A: array of Integer);
begin
  WriteLn(' len=', Length(A), ' [0]=', A[0]);
end;

procedure Show(const A: array of Integer);
begin
  WriteLn(' len=', Length(A), ' [0]=', A[0]);
end;

var
  c: TOpenCb;
  o: TObjCb;
  sk: TSink;
  v: array of Integer;
begin
  SetLength(v, 3); v[0] := 7; v[1] := 8; v[2] := 9;

  Write('literal direct  :'); Show([7,8,9]);
  Write('var     direct  :'); Show(v);

  c := @Show;
  Write('literal indirect:'); c([7,8,9]);
  Write('var     indirect:'); c(v);

  sk := TSink.Create;
  o := @sk.M;
  Write('ofobj   lit ind :'); o([7,8,9]);
  Write('ofobj   var ind :'); o(v);
end.

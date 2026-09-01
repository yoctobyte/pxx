{ A PROMOTABLE INT REACHED THROUGH ANYTHING BUT A PLAIN IDENTIFIER.

  `promoint64` is a 16-byte {tag, payload} slot, and promocore's entire calling
  convention is that a promo rvalue IS ITS SLOT ADDRESS. Five places implemented
  that convention and all five recognised only AN_IDENT, so an array element, a
  record/class field and a pointer dereference were wrong in BOTH directions:

    a[i] := n      fell past the promo store arm into the ordinary integer
                   store, writing a machine word over the {tag, payload} slot
    n := a[i]      lowered to the slot LOADED INTO A REGISTER and handed that
                   16-byte struct to a helper that dereferences it

  So the first READ of a[i], r.v or p^ segfaulted -- on the pinned compiler and
  at -O0, -O1, -O2 and -O3 alike -- while the identical value in a scalar local
  was correct. `WriteLn(a[i])` segfaulted in a program where `c := a[i];
  WriteLn(c)` printed the right answer, which is the shape that names the defect:
  the difference was not the value but which consumer asked for it.

  WHY THIS FILE READS ELEMENTS RATHER THAN JUST DECLARING THEM. Its neighbour
  test_promoint_local_array_zero_init.pas already covers a promo array, passed
  throughout, and could not see any of this: it takes `@a[i]` and inspects the
  tag word, and taking an ADDRESS was the one direction that always worked. A
  test of a container that never reads an element out of it is testing the
  container.

  VALUES PAST 2^63 ON PURPOSE, not for arithmetic coverage -- that is
  test_promoint.pas's job -- but because an inline-tier slot survives being
  copied as a machine word by accident, and a heap-tier one does not. The
  expected digits below are CPython's.

  Control: so_scalar and so_global are the two shapes that always worked. If
  they ever fail, the fix broke the case it was meant to leave alone.

  bug-a-a-static-array-of-promo-ints-releases-only-element-zero }
program test_promoint_lvalue_shapes;
{$mode objfpc}{$H+}

type
  TRec = class
    v: promoint64;
  end;
  TPlain = record
    v: promoint64;
    tail: Int64;      { a following field, so a 16-byte write past v is visible }
  end;
  PPromo = ^promoint64;

var
  ok, total: Integer;
  g: promoint64;

procedure Check(const what: string; const got, want: AnsiString);
begin
  Inc(total);
  if got = want then
  begin
    Inc(ok);
    WriteLn('ok   ', what);
  end
  else
    WriteLn('FAIL ', what, ' got=', got, ' want=', want);
end;

{ Takes its argument BY VALUE and stringifies the copy, so every call below
  goes through the argument path -- which had the same identifier-only rule --
  rather than through `@a[i]`, the one direction that never broke. }
function S(const p: promoint64): AnsiString;
var t: promoint64;
begin
  t := p;
  S := PXXPromoToStr(@t);
end;

{ ---- static array ---- }
procedure ArrSmall;
var a: array[0..3] of promoint64; i: Integer; acc: promoint64;
begin
  for i := 0 to 3 do a[i] := i + 1;
  acc := 0;
  for i := 0 to 3 do acc := acc + a[i];
  Check('static array store+read', S(acc), '10');
  Check('static array element direct', S(a[2]), '3');
end;

procedure ArrBig;
var a: array[0..2] of promoint64; i: Integer;
begin
  a[0] := 1;
  for i := 1 to 80 do a[0] := a[0] * 3;
  Check('static array heap tier', S(a[0]),
        '147808829414345923316083210206383297601');
  a[1] := a[0] + 1;
  a[2] := a[1] * a[0];
  Check('element-to-element arithmetic', S(a[2]),
        '21847450052839212624230656502990235142714858934327097804128907158869315652802');
end;

{ ---- dynamic array ---- }
procedure DynArr;
var a: array of promoint64; i: Integer; acc: promoint64;
begin
  SetLength(a, 5);
  for i := 0 to 4 do a[i] := 10;
  for i := 0 to 4 do a[i] := a[i] * a[i];
  acc := 0;
  for i := 0 to 4 do acc := acc + a[i];
  Check('dynamic array store+read', S(acc), '500');
end;

{ ---- record field ---- }
procedure RecField;
var r: TPlain;
begin
  r.tail := -1;
  r.v := 1;
  r.v := r.v * 1000000000000;
  r.v := r.v * 1000000000000;
  Check('record field heap tier', S(r.v), '1000000000000000000000000');
  Check('record field left neighbour alone', S(r.tail), '-1');
end;

{ ---- class field ---- }
procedure ClassField;
var c: TRec;
begin
  c := TRec.Create;
  c.v := 7;
  c.v := c.v + 5;
  Check('class field store+read', S(c.v), '12');
  c.Free;
end;

{ ---- pointer dereference ---- }
procedure Deref;
var c: promoint64; p: PPromo;
begin
  c := 5;
  p := @c;
  p^ := p^ * 100000000000000000000;
  Check('deref store+read', S(p^), '500000000000000000000');
  Check('deref aliases the slot', S(c), '500000000000000000000');
end;

{ ---- the consumer that had its own copy of the rule ---- }
procedure WriteDirect;
var a: array[0..1] of promoint64;
begin
  a[0] := 1;
  a[0] := a[0] * 100000000000000000000;
  { `WriteLn(a[0])` is the call that segfaulted while `c := a[0]; WriteLn(c)`
    was correct, so it is asserted through the write path and not through S(). }
  Write('direct-write ');
  WriteLn(a[0]);
end;

{ ---- controls: the shapes that always worked ---- }
procedure Controls;
var s: promoint64; i: Integer;
begin
  s := 1;
  for i := 1 to 80 do s := s * 3;
  Check('CONTROL scalar local', S(s),
        '147808829414345923316083210206383297601');
  g := 1;
  for i := 1 to 40 do g := g * 3;
  Check('CONTROL global', S(g), '12157665459056928801');
end;

begin
  ok := 0; total := 0;
  ArrSmall;
  ArrBig;
  DynArr;
  RecField;
  ClassField;
  Deref;
  WriteDirect;
  Controls;
  WriteLn('promoint-lvalue-shapes ', ok, '/', total);
end.

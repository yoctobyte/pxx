{ `Integer(v) := x` -- a type cast used as the TARGET of an assignment, over an
  ordinary lvalue rather than a pointer deref.

  Before bug-p-cast-as-lvalue-only-accepts-a-pointer-deref, only the deref form
  `Integer(p^) := x` parsed; everything here answered

      cast-as-lvalue statement requires a pointer deref inside the cast

  including the one shape that has no other spelling: writing through an
  UNTYPED `var x` parameter. Reading one already worked (`Integer(x)` as an
  r-value), so a Move/FillChar-shaped routine could look at its argument and
  not store to it.

  Every expected value is fpc 3.2.2 -Mobjfpc -O1's. }
program test_cast_as_lvalue_over_a_variable;

type
  TRec = record a: Integer; c: Char; end;

var
  i, guardLo, guardHi, fails: Integer;
  b, bb: Byte;
  r: TRec;
  arr: array[0..3] of Integer;
  carr: array[0..3] of Char;
  p: ^Integer;

procedure PokeInt(var x; v: Integer);   { untyped var param: 4-byte store }
begin
  Integer(x) := v;
end;

procedure PokeByte(var x; v: Byte);     { same param, 1-byte store }
begin
  Byte(x) := v;
end;

function PeekInt(const x): Integer;     { the read side, which already worked }
begin
  PeekInt := Integer(x);
end;

procedure Chk(const nm: string; got, want: Int64);
begin
  if got = want then WriteLn(nm, ' ok')
  else begin WriteLn(nm, ' FAIL got=', got, ' want=', want); Inc(fails); end;
end;

begin
  fails := 0;

  { the pointer-deref form must keep working }
  i := 0; p := @i; Integer(p^) := 33;
  Chk('deref', i, 33);

  { a plain variable, a field, an array element }
  i := 5;    Integer(i) := 7;          Chk('plainvar', i, 7);
  r.a := 1;  Integer(r.a) := 11;       Chk('field', r.a, 11);
  arr[2] := 1; Integer(arr[2]) := 22;  Chk('element', arr[2], 22);

  { a same-size cast that is not the declared type }
  bb := 65; Char(bb) := 'z';           Chk('byte-as-char', bb, 122);
  carr[0] := 'a'; Char(carr[0]) := 'q'; Chk('chararr', Ord(carr[0]), 113);
  r.c := 'q'; Char(r.c) := 'w';        Chk('charfield', Ord(r.c), 119);

  { writing through an UNTYPED var parameter -- the shape with no alternative
    spelling. The guards on either side of `i` catch a store that used the
    parameter's DECLARED width (tyPointer, 8 bytes) instead of the cast's. }
  guardLo := $11111111; guardHi := $22222222;
  i := 1; PokeInt(i, 99);
  Chk('untyped.int', i, 99);
  Chk('untyped.guardLo', guardLo, $11111111);
  Chk('untyped.guardHi', guardHi, $22222222);

  b := 1; PokeByte(b, 7);
  Chk('untyped.byte', b, 7);

  { the same untyped param against a field and an element }
  r.a := 0;  PokeInt(r.a, 44);   Chk('untyped.field', r.a, 44);
  arr[1] := 0; PokeInt(arr[1], 55); Chk('untyped.element', arr[1], 55);

  { the read side, unchanged }
  i := 55;
  Chk('untyped.read', PeekInt(i), 55);

  if fails = 0 then WriteLn('ALL OK') else WriteLn('FAILURES ', fails);
end.

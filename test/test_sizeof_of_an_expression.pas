{ SizeOf takes an EXPRESSION, not only a type name or a variable.

  Every row below was a compile error before feature-p-sizeof-of-an-expression:
  the operand was scanned as a NAME (optionally `.field` and one `[...]`), so
  the parser stopped at the first operator and reported "expected )".

  Expected values are fpc 3.2.2 -Mobjfpc -O1's, EXCEPT the two marked below
  where pxx's own documented dialect rule differs -- those are asserted at the
  pxx value deliberately, so a future change to either rule fails here loudly
  rather than drifting.

  SizeOf must not EVALUATE its operand: F below prints when called, and the
  program's output says whether it was. }
program test_sizeof_of_an_expression;

type
  TR = record a, b: Integer; end;

var
  i: Integer;
  q: Int64;
  d: Double;
  c: Char;
  s: string;
  p: ^Integer;
  a: array[0..3] of Byte;
  r: TR;
  calls: Integer;

function F(x: Integer): Integer;
begin
  Inc(calls);
  F := x;
end;

procedure Chk(const nm: string; got, want: Integer);
begin
  if got = want then WriteLn(nm, ' ok')
  else WriteLn(nm, ' FAIL got=', got, ' want=', want);
end;

begin
  i := 3; q := 3; d := 1.5; c := 'x'; s := 'abc'; p := @i; a[0] := 1;
  r.a := 1; calls := 0;

  { the shapes that already worked -- they must keep working, since the fix is
    a DISPATCH in front of the name path and not a replacement of it }
  Chk('typename', SizeOf(Integer), 4);
  Chk('keywordty', SizeOf(Double), 8);
  Chk('recordty', SizeOf(TR), 8);
  Chk('var', SizeOf(i), 4);
  Chk('field', SizeOf(r.a), 4);
  Chk('arrayvar', SizeOf(a), 4);
  Chk('arrayelem', SizeOf(a[0]), 1);
  Chk('arrayidxvar', SizeOf(a[i]), 1);
  Chk('ptrvar', SizeOf(p), 8);
  Chk('recvar', SizeOf(r), 8);

  { the new ones }
  Chk('deref', SizeOf(p^), 4);
  Chk('addrof', SizeOf(@i), 8);
  Chk('add', SizeOf(i + 1), 8);
  Chk('mul', SizeOf(i * 2), 8);
  Chk('neg', SizeOf(-i), 8);
  Chk('div', SizeOf(i div 2), 8);
  Chk('call', SizeOf(Abs(i)), 4);
  Chk('paren', SizeOf((i)), 4);
  Chk('cmp', SizeOf(i > 0), 1);
  Chk('cast', SizeOf(Byte(i)), 1);
  Chk('i64add', SizeOf(q + 1), 8);
  Chk('dblmul', SizeOf(d * 2), 8);
  Chk('strindex', SizeOf(s[1]), 1);
  Chk('elemcount', SizeOf(i) div SizeOf(c), 4);

  { pxx dialect, NOT fpc: shifts happen at native width and are not truncated
    to the operand's declared type, so `i shl 1` is Int64 here and Integer in
    fpc. devdocs/dev/pascal-dialect-divergences.md, decided in
    decide-shift-operator-promotion-width. }
  Chk('shift-dialect', SizeOf(i shl 1), 8);

  { pxx's Length returns Integer; fpc's returns SizeInt (8). Not a SizeOf
    question -- recorded here because this is where it becomes visible. }
  Chk('lengthret', SizeOf(Length(a)), 4);

  { the operand is never evaluated }
  Chk('nosideeffect', SizeOf(F(i)), 4);
  Chk('callcount', calls, 0);
  i := F(7);
  Chk('callcount2', calls, 1);
end.

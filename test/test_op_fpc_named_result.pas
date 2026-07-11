program test_op_fpc_named_result;

{ FPC-compat operator declarations: named-result form, `/` and `mod` in the
  declarable op set, and mixing both result forms in one program. }

type
  TFrac = record
    Num, Den: Integer;
  end;

{ FPC named-result form }
operator + (a, b: TFrac) z: TFrac;
begin
  z.Num := a.Num * b.Den + b.Num * a.Den;
  z.Den := a.Den * b.Den;
end;

{ named result with early Exit: alias semantics — the value assigned before
  Exit must be the return value }
operator - (a, b: TFrac) r: TFrac;
begin
  r.Num := a.Num * b.Den - b.Num * a.Den;
  r.Den := a.Den * b.Den;
  if r.Den <> 0 then Exit;
  r.Num := -999;
end;

{ `/` overload, FPC named-result form }
operator / (a, b: TFrac) q: TFrac;
begin
  q.Num := a.Num * b.Den;
  q.Den := a.Den * b.Num;
end;

{ `mod` overload, pxx Result form (both forms in one program) }
operator mod (a, b: TFrac): TFrac;
begin
  Result.Num := (a.Num * b.Den) mod (b.Num * a.Den);
  Result.Den := a.Den * b.Den;
end;

{ pxx Result form still works }
operator * (a, b: TFrac): TFrac;
begin
  Result.Num := a.Num * b.Num;
  Result.Den := a.Den * b.Den;
end;

var
  x, y, s: TFrac;
begin
  x.Num := 1; x.Den := 2;
  y.Num := 1; y.Den := 3;

  s := x + y;                    { 5/6 }
  writeln(s.Num, '/', s.Den);

  s := x - y;                    { 1/6, via early Exit }
  writeln(s.Num, '/', s.Den);

  s := x / y;                    { 3/2 }
  writeln(s.Num, '/', s.Den);

  s := x * y;                    { 1/6 }
  writeln(s.Num, '/', s.Den);

  s := x mod y;                  { (3 mod 2)/6 = 1/6 }
  writeln(s.Num, '/', s.Den);

  s := x + y - x;                { chained: 5/6 - 1/2 = 4/12 }
  writeln(s.Num, '/', s.Den);
end.

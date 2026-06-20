{ Regression (x86-64): the exact bignum shape — a record with a managed
  (dynamic-array) field, built by a function and passed as a temporary to a
  `const` record parameter. Materialized into a hidden local; its address is
  passed. Proves bug-const-byref-record-param-temp on the real managed-record
  case, including the aggregate managed-record return path on cross targets. }
program test_const_record_temp_managed;

type
  TBig = record
    neg:   Boolean;
    limbs: array of Int64;
  end;

function MakeBig(v: Int64): TBig;
begin
  SetLength(Result.limbs, 1);
  Result.limbs[0] := v;
  Result.neg := False;
end;

function AddBig(const a, b: TBig): TBig;
begin
  SetLength(Result.limbs, 1);
  Result.limbs[0] := a.limbs[0] + b.limbs[0];
  Result.neg := False;
end;

function SumBig(const a: TBig): Int64;
begin
  SumBig := a.limbs[0];
end;

var
  p: TBig;
begin
  Writeln(SumBig(MakeBig(7)));                       { 7 }
  p := AddBig(MakeBig(40), MakeBig(2));
  Writeln(p.limbs[0]);                               { 42 }
  p := AddBig(AddBig(MakeBig(10), MakeBig(20)), AddBig(MakeBig(5), MakeBig(7)));
  Writeln(p.limbs[0]);                               { 42 }
end.

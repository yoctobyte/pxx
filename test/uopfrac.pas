unit uopfrac;

{ Unit-scoped operator overloads (bug-unit-operator-def-silently-skipped):
  definitions in a unit implementation must register like program-scoped ones.
  Also exercises the FPC named-result form and the `/` operator
  (feature-pascal-operator-decl-fpc-compat). }

interface

type
  TFrac = record
    Num, Den: Integer;
  end;

procedure CheckInsideUnit;

implementation

{ FPC named-result form }
operator + (a, b: TFrac) z: TFrac;
begin
  z.Num := a.Num * b.Den + b.Num * a.Den;
  z.Den := a.Den * b.Den;
end;

{ `/` overload }
operator / (a, b: TFrac) q: TFrac;
begin
  q.Num := a.Num * b.Den;
  q.Den := a.Den * b.Num;
end;

{ pxx Result form in the same unit }
operator * (a, b: TFrac): TFrac;
begin
  Result.Num := a.Num * b.Num;
  Result.Den := a.Den * b.Den;
end;

procedure CheckInsideUnit;
var x, y, s: TFrac;
begin
  x.Num := 1; x.Den := 2;
  y.Num := 1; y.Den := 3;
  s := x + y;
  writeln('in:', s.Num, '/', s.Den);
end;

end.

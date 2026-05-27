program test_op_overload;

type
  TWeight = class
    Value: Integer;
  end;

  TPoint = class
    X: Integer;
    Y: Integer;
  end;

{ Comparison operators for TWeight }
operator < (a, b: TWeight): Boolean;
begin
  Result := a.Value < b.Value;
end;

operator > (a, b: TWeight): Boolean;
begin
  Result := a.Value > b.Value;
end;

operator = (a, b: TWeight): Boolean;
begin
  Result := a.Value = b.Value;
end;

{ Arithmetic operator for TPoint }
operator + (a, b: TPoint): TPoint;
var r: TPoint;
begin
  r := TPoint.Create;
  r.X := a.X + b.X;
  r.Y := a.Y + b.Y;
  Result := r;
end;

var
  w1, w2, w3: TWeight;
  p1, p2, p3: TPoint;
begin
  w1 := TWeight.Create; w1.Value := 5;
  w2 := TWeight.Create; w2.Value := 10;
  w3 := TWeight.Create; w3.Value := 5;

  { < operator }
  if w1 < w2 then writeln(1) else writeln(0);   { 1 }
  if w2 < w1 then writeln(1) else writeln(0);   { 0 }

  { > operator }
  if w2 > w1 then writeln(1) else writeln(0);   { 1 }
  if w1 > w2 then writeln(1) else writeln(0);   { 0 }

  { = operator }
  if w1 = w3 then writeln(1) else writeln(0);   { 1 }
  if w1 = w2 then writeln(1) else writeln(0);   { 0 }

  { + operator on TPoint }
  p1 := TPoint.Create; p1.X := 3; p1.Y := 4;
  p2 := TPoint.Create; p2.X := 7; p2.Y := 2;
  p3 := p1 + p2;
  writeln(p3.X);   { 10 }
  writeln(p3.Y);   { 6 }
end.

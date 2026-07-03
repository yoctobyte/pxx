program test_arm32_virtual_wide;
type
  TBase = class
    FSum: Integer;
    procedure Add(a, b, c, d, e: Integer); virtual;
    function Mix(a, b, c, d, e, f: Integer): Integer; virtual;
  end;
  TChild = class(TBase)
    procedure Add(a, b, c, d, e: Integer); override;
    function Mix(a, b, c, d, e, f: Integer): Integer; override;
  end;

procedure TBase.Add(a, b, c, d, e: Integer);
begin
  FSum := a + b + c + d + e;
end;

function TBase.Mix(a, b, c, d, e, f: Integer): Integer;
begin
  Mix := a + b + c + d + e + f;
end;

procedure TChild.Add(a, b, c, d, e: Integer);
begin
  FSum := a * b * c * d * e;
end;

function TChild.Mix(a, b, c, d, e, f: Integer): Integer;
begin
  Mix := a - b + c - d + e - f + 100;
end;

var
  o: TBase;
begin
  o := TBase.Create;
  o.Add(1, 2, 3, 4, 5);        { 6 words incl Self }
  writeln(o.FSum);              { 15 }
  writeln(o.Mix(1, 2, 3, 4, 5, 6));  { 21 }
  o := TChild.Create;
  o.Add(1, 2, 3, 4, 5);
  writeln(o.FSum);              { 120 }
  writeln(o.Mix(9, 2, 3, 4, 5, 6));  { 9-2+3-4+5-6+100 = 105 }
end.

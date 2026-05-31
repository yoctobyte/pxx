unit math;
interface
uses math_ext;

function Min(a, b: Integer): Integer;
function Max(a, b: Integer): Integer;
function Power(base, exponent: Integer): Integer;
function Gcd(a, b: Integer): Integer;
function Lcm(a, b: Integer): Integer;

implementation

function Min(a, b: Integer): Integer;
begin
  if a < b then
    Result := a
  else
    Result := b;
end;

function Max(a, b: Integer): Integer;
begin
  if a > b then
    Result := a
  else
    Result := b;
end;

function Power(base, exponent: Integer): Integer;
var
  i, res: Integer;
begin
  res := 1;
  for i := 1 to exponent do
    res := res * base;
  Result := res;
end;

function Gcd(a, b: Integer): Integer;
var
  temp, x, y: Integer;
begin
  x := a;
  y := b;
  while y <> 0 do
  begin
    temp := y;
    y := x mod y;
    x := temp;
  end;
  Result := x;
end;

function Lcm(a, b: Integer): Integer;
begin
  if (a = 0) or (b = 0) then
    Result := 0
  else
    Result := (a * b) div Gcd(a, b);
end;

end.

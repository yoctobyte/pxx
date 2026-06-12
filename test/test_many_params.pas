program TestManyParams;
{ Regression for bug-many-param-call-corruption: internal x86-64 calls with
  more than 6 parameters used to pop the wrong (topmost) args into the
  argument registers and leak the rest on the stack. Procs with >6 params now
  use the all-stack internal convention. Covers the three patched call paths:
  plain IR_CALL, constructor calls, and virtual dispatch — with locals,
  nested calls, by-ref params, and sub-word param sizes (the shifts are
  order-sensitive, so a commutative sum would not catch them). }

type
  TWide = class
    FAcc: Integer;
    constructor Create(a, b, c, d, e, f, g: Integer);
    function Mix(a, b, c, d, e, f, g, h: Integer): Integer; virtual;
  end;

  TWideChild = class(TWide)
    function Mix(a, b, c, d, e, f, g, h: Integer): Integer; override;
  end;

constructor TWide.Create(a, b, c, d, e, f, g: Integer);
begin
  { Order-sensitive: any arg shift changes the value. }
  FAcc := a + b * 10 + c * 100 + d * 1000 + e * 10000 + f * 100000 + g * 1000000;
end;

function TWide.Mix(a, b, c, d, e, f, g, h: Integer): Integer;
begin
  Result := a - b + c - d + e - f + g - h;
end;

function TWideChild.Mix(a, b, c, d, e, f, g, h: Integer): Integer;
begin
  Result := a * 2 - b + c - d + e - f + g - h;
end;

function Pair(x, y: Integer): Integer;
begin
  Result := x * 10 + y;
end;

procedure Show7(a, b, c, d, e, f, g: Integer);
begin
  writeln(a, ' ', b, ' ', c, ' ', d, ' ', e, ' ', f, ' ', g);
end;

function Nest9(a, b, c, d, e, f, g, h, i: Integer): Integer;
var lo, hi: Integer;
begin
  { Locals plus nested >6-param and 2-param calls from inside the callee. }
  lo := Pair(a, b);
  hi := Pair(h, i);
  Show7(c, d, e, f, g, lo, hi);
  Result := lo + hi * 100;
end;

procedure RefMix(a, b, c: Integer; var acc: Integer; d, e, f, g: Integer);
begin
  acc := acc + a + b * 10 + c * 100 + d * 1000 + e * 10000 + f * 100000 + g * 1000000;
end;

function Sized8(a: Byte; b: Word; c: Integer; d: Int64; e: Byte; f: Word; g: Integer; h: Int64): Int64;
begin
  Result := a + b * 100 + c * 10000 + d * 1000000 + e + f * 100 + g * 10000 + h * 1000000;
end;

var
  o: TWide;
  v: Integer;
begin
  Show7(1, 2, 3, 4, 5, 6, 7);
  writeln(Nest9(1, 2, 3, 4, 5, 6, 7, 8, 9));
  v := 5;
  RefMix(1, 2, 3, v, 4, 5, 6, 7);
  writeln(v);
  writeln(Sized8(1, 2, 3, 4, 5, 6, 7, 8));
  o := TWide.Create(1, 2, 3, 4, 5, 6, 7);
  writeln(o.FAcc);
  writeln(o.Mix(100, 1, 2, 3, 4, 5, 6, 7));
  o := TWideChild.Create(1, 2, 3, 4, 5, 6, 7);
  writeln(o.Mix(100, 1, 2, 3, 4, 5, 6, 7));
end.

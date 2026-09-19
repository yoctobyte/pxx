program test_xtensa_call_arg_classes;
{ Argument CLASSES through every call shape on xtensa, with the x86-64 run as
  the oracle. Direct calls always marshalled Int64/Double/Single by class; the
  virtual, indirect and constructor sites each carried their own ladder that
  knew only records, so an Int64 or a Double went over as ONE word. A 32-bit
  value survives that (the high word it drops is zero), which is why `id` and
  `indsmall` pass on the broken compiler and the big rows do not: NilPy passes
  every int as Int64 through a method call, and an ESP32-S3 program printed
  its quotients divided by 16. See XtensaPushArgByClass.

  `wide` is the other half: more argument words than the windowed register
  set plus the fixed outgoing region hold (22 words and up used to be refused
  with "too many arguments"). Those words now go in a region carved below sp
  with MOVSP for the length of the call. }
{$mode objfpc}
type
  TB = class
    function Id(dist: Int64): Int64; virtual;
    function Mix(a: Integer; b: Int64; c: Double; d: Single): Int64; virtual;
  end;
  TFn = function(a: Integer; b: Int64; c: Double): Int64;

function TB.Id(dist: Int64): Int64; begin Result := dist; end;
function TB.Mix(a: Integer; b: Int64; c: Double; d: Single): Int64;
begin Result := a + b + Trunc(c * 10) + Trunc(d * 100); end;

function F3(a: Integer; b: Int64; c: Double): Int64;
begin Result := a * 1000 + b + Trunc(c * 10); end;

{ 13 Int64 = 26 argument words }
function Wide(a, b, c, d, e, f, g, h, i, j, k, l, m: Int64): Int64;
begin
  Result := a + 2*b + 3*c + 4*d + 5*e + 6*f + 7*g + 8*h + 9*i + 10*j
            + 11*k + 12*l + 13*m;
end;

var o: TB; p: TFn; small: Integer;
begin
  o := TB.Create;
  small := 120;
  WriteLn('id ', o.Id(small));
  WriteLn('idbig ', o.Id(Int64(5000000000)));
  WriteLn('mix ', o.Mix(3, Int64(7000000000), 2.5, 1.25));
  p := @F3;
  WriteLn('ind ', p(4, Int64(9000000000), 1.5));
  WriteLn('indsmall ', p(4, small, small));
  WriteLn('wide ', Wide(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, Int64(10000000000)));
  WriteLn('widenest ', Wide(Wide(1,1,1,1,1,1,1,1,1,1,1,1,1), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, small));
end.

{$mode objfpc}{$H+}{$modeswitch advancedrecords}
{ Record operator overloads with MIXED operand types (`TVec * Integer`).

  Two bugs, the second hidden behind the first:

  * The in-record `class operator` SIGNATURE is skipped by scanning to the
    terminating ';' -- and the scan was depth-blind, so it stopped at the ';'
    that SEPARATES parameter groups, leaving `k: Integer): TVec;` to be parsed
    as a field. Every mixed-type operator was a syntax error; the homogeneous
    `(const a, b: TVec)` form parsed only because it has no inner ';'.

  * With the signature parsing, the OPERATOR TABLE turned out to be keyed on
    the LEFT operand alone, so `TVec + TVec` and `TVec + Integer` collided and
    the first registered always won -- `a + 5` silently called the record/record
    overload. Lookup now prefers an entry whose SECOND parameter matches the
    right operand, falling back to the old first-match so single-overload
    programs are unaffected.

  Every row diffed against FPC.
  bug-a-a-mixed-type-record-operator-signature-fails-to-parse }
program test_op_overload_mixed_operands;
uses SysUtils;
type
  TVec = record
    x, y: Integer;
    class operator + (const a, b: TVec): TVec;
    class operator - (const a, b: TVec): TVec;
    class operator = (const a, b: TVec): Boolean;
    class operator * (const a: TVec; k: Integer): TVec;
    function Len2: Integer;
    class function Zero: TVec; static;
  end;
class operator TVec.+(const a, b: TVec): TVec; begin Result.x := a.x+b.x; Result.y := a.y+b.y; end;
class operator TVec.-(const a, b: TVec): TVec; begin Result.x := a.x-b.x; Result.y := a.y-b.y; end;
class operator TVec.=(const a, b: TVec): Boolean; begin Result := (a.x=b.x) and (a.y=b.y); end;
class operator TVec.*(const a: TVec; k: Integer): TVec; begin Result.x := a.x*k; Result.y := a.y*k; end;
function TVec.Len2: Integer; begin Result := x*x + y*y; end;
class function TVec.Zero: TVec; begin Result.x := 0; Result.y := 0; end;

function V(ax, ay: Integer): TVec; begin Result.x := ax; Result.y := ay; end;
function S(const a: TVec): string; begin Result := '(' + IntToStr(a.x) + ',' + IntToStr(a.y) + ')'; end;

var a, b, c: TVec; arr: array[0..2] of TVec; i: Integer;
begin
  a := V(1,2); b := V(3,4);
  WriteLn('add   ', S(a+b));
  WriteLn('sub   ', S(b-a));
  WriteLn('mul   ', S(a*3));
  WriteLn('chain ', S(a+b-a));
  WriteLn('eq    ', a = V(1,2), ' ', a = b);
  WriteLn('meth  ', a.Len2, ' ', (a+b).Len2);
  WriteLn('zero  ', S(TVec.Zero));
  c := TVec.Zero;
  for i := 0 to 2 do begin arr[i] := V(i, i*2); c := c + arr[i]; end;
  WriteLn('accum ', S(c));
  WriteLn('elem  ', S(arr[1]), ' ', arr[2].Len2);
  WriteLn('nest  ', S(V(1,1) + V(2,2) + V(3,3)));
  { the collision row: both TVec+TVec and TVec*Integer exist; each use site
    must pick by the RIGHT operand, not by registration order }
  WriteLn('pick  ', S(a + b), ' ', S(a * 3));
  WriteLn('OP OVERLOAD MIXED OPERANDS OK');
end.

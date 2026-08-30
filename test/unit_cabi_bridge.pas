unit unit_cabi_bridge;
{ A Pascal unit whose implementation is a C translation unit, wrapping each C
  function so a PASCAL caller reaches a bodied C callee.

  Each wrapper's parameter list mirrors the C signature exactly, so the shape
  under test is the convention itself and nothing else: which register bank a
  float lands in, whether a 64-bit argument needs an even-numbered pair, and
  which end of the stack argument block is argument zero. }
interface
function DblFirst(x: Double; n: Integer): Double;
function IntFirst(n: Integer; x: Double): Double;
function ThreeInts(a, b, c: Integer): Integer;
function TwoDbl(a, b: Double): Double;
function Flt(f: Single; n: Integer): Single;
implementation
uses './cabi_bridge.c';
function DblFirst(x: Double; n: Integer): Double; begin DblFirst := cee_dbl_first(x, n); end;
function IntFirst(n: Integer; x: Double): Double; begin IntFirst := cee_int_first(n, x); end;
function ThreeInts(a, b, c: Integer): Integer;    begin ThreeInts := cee_three_ints(a, b, c); end;
function TwoDbl(a, b: Double): Double;            begin TwoDbl := cee_two_dbl(a, b); end;
function Flt(f: Single; n: Integer): Single;      begin Flt := cee_flt(f, n); end;
end.

{$mode objfpc}
program test_inline_result_narrows;

{ A function whose whole body is `Result := E` must narrow E to the DECLARED
  result type — and it must do so when the call is INLINED, which is where it
  stopped.

  The -O2 inliner's shape 1 retains the RHS expression and drops the
  assignment, and the narrowing lived in that store. So `F(4294967299)` printed
  4294967299 at -O2 and 3 at -O0/-O1, on x86-64 and aarch64 only, while the
  SAME function with any second statement was right — that is shape 3, which
  allocates a properly typed Result temp and stores through it. Narrowing cases
  now go to shape 3.

  Rows 5 and 6 are the commoner form and are why this is not a corner case:
  `Result := a + 1` on an Integer function promotes to 64 bits for the
  arithmetic, so EVERY such function was returning an unwrapped value at -O2.
  AddOne(MaxInt) is -2147483648 in FPC and at -O0; it was 2147483648 here.

  Rows 7-9 must NOT change: they widen or keep the width, still take shape 1,
  and are here so a future guard cannot pass by disabling the optimisation.
  bug-a-function-result-assignment-does-not-narrow-to-the-result-type }

function ByName(a: Int64): Integer;  begin ByName := a; end;
function ByResult(a: Int64): Integer; begin Result := a; end;
function SmallRes(a: Int64): SmallInt; begin SmallRes := a; end;
function ByteRes(a: Int64): Byte;    begin ByteRes := a; end;
function AddOne(a: Integer): Integer; begin AddOne := a + 1; end;
function Dbl(a: Integer): Integer;   begin Dbl := a * 2; end;
function Widen(a: Integer): Int64;   begin Widen := a; end;
function Same(a: Int64): Int64;      begin Same := a * 2; end;
function Keep(a: Byte): Byte;        begin Keep := a; end;

begin
  writeln(ByName(4294967299));      { 3 }
  writeln(ByResult(4294967299));    { 3 }
  writeln(SmallRes(4294967299));    { 3 }
  writeln(ByteRes(4294967299));     { 3 }
  writeln(AddOne(2147483647));      { -2147483648 — wraps, like FPC and -O0 }
  writeln(Dbl(2000000000));         { -294967296 }
  writeln(Widen(-5));               { -5   — widening, shape 1, unchanged }
  writeln(Same(4294967299));        { 8589934598 — same width, unchanged }
  writeln(Keep(200));               { 200  — same width, unchanged }
end.

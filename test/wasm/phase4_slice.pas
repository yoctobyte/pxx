{ SPDX-License-Identifier: MPL-2.0 }
{ Phase 4 slice oracle — direct calls. Same two-role shape as the other slices.

  On a register target a call is where the argument-passing ABI lives; riscv32
  spends 508 lines spilling arguments and reloading them into a0..a7. wasm has
  no registers and no calling convention to implement — arguments go on the
  operand stack in order and `call` consumes them — so what is left to get
  wrong is not the ABI but the FUNCTION INDEX and the SIGNATURE, and those fail
  in ways the differential is better placed to catch than the validator:

    Chain      f calls g calls h. A wrong index calls the wrong function, and
               if the signatures happen to match, the module validates.
    Fact, Fib  self-recursion: the callee's slot is reserved while its own body
               is mid-emission.
    IsEven     mutual recursion through a FORWARD declaration — the case that
               forced locals to become per-body. IsEven's body is emitted while
               IsOdd's slot exists but has no body yet, so the two are
               interleaved in a way single-pass emission cannot linearise.
    Apply      a call whose argument is itself a call, so the operand stack
               holds a half-built argument list across a nested call.
    Widen      an Int64 argument and an Int64 result crossing a call boundary,
               and an Integer argument coerced to an Int64 parameter — the
               conversion the IR does not insert.
    Bump       a procedure taking a `var` parameter: the ARGUMENT is an
               address, so the parameter is i32 whatever it is declared as.
    Discard    a function called for its side effect. wasm requires an empty
               operand stack at the end of a statement, so the result has to be
               dropped; forgetting is a validation failure, dropping the wrong
               thing is not. }
program Phase4Slice;

var
  Counter: Integer;

function H(x: Integer): Integer;
begin H := x * 3; end;

function G(x: Integer): Integer;
begin G := H(x) + 1; end;

function Chain(x: Integer): Integer;
begin Chain := G(x) * 2; end;

function Fact(n: Integer): Integer;
begin
  if n <= 1 then Fact := 1 else Fact := n * Fact(n - 1);
end;

function Fib(n: Integer): Integer;
begin
  if n < 2 then Fib := n else Fib := Fib(n - 1) + Fib(n - 2);
end;

function IsOdd(n: Integer): Integer; forward;

function IsEven(n: Integer): Integer;
begin
  if n = 0 then IsEven := 1 else IsEven := IsOdd(n - 1);
end;

function IsOdd(n: Integer): Integer;
begin
  if n = 0 then IsOdd := 0 else IsOdd := IsEven(n - 1);
end;

function Apply(x: Integer): Integer;
begin Apply := H(G(H(x))); end;

function Widen(a: Integer; b: Int64): Int64;
begin Widen := WidenHelp(a) + b; end;

function WidenHelp(a: Integer): Int64;
begin WidenHelp := a; end;

procedure Bump(var v: Integer; by: Integer);
begin v := v + by; end;

function UseBump(x: Integer): Integer;
var t: Integer;
begin
  t := x;
  Bump(t, 5);
  Bump(t, 100);
  UseBump := t;
end;

function SideEffect(n: Integer): Integer;
begin
  Counter := Counter + n;
  SideEffect := Counter;
end;

function Discard(n: Integer): Integer;
begin
  SideEffect(n);
  SideEffect(n);
  Discard := Counter;
end;

function Many(a, b, c, d, e, f, g, h: Integer): Integer;
begin
  Many := a + b * 2 + c * 3 + d * 4 + e * 5 + f * 6 + g * 7 + h * 8;
end;

function UseMany(x: Integer): Integer;
begin UseMany := Many(x, x + 1, x + 2, x + 3, x + 4, x + 5, x + 6, x + 7); end;

{$ifndef WASM_NOMAIN}
begin
  writeln(Chain(5));
  writeln(Fact(10));
  writeln(Fib(15));
  writeln(IsEven(10));
  writeln(IsEven(7));
  writeln(IsOdd(7));
  writeln(Apply(2));
  writeln(Widen(7, 10000000000));
  writeln(UseBump(1));
  writeln(Discard(3));
  writeln(Discard(3));
  writeln(UseMany(1));
end.
{$else}
begin
end.
{$endif}

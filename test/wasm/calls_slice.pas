{ SPDX-License-Identifier: MPL-2.0 }
{ Indirect-call slice oracle — procedural variables. Same two-role shape as the
  other slices.

  wasm has no code addresses, so `@Proc` and a procedural variable become an
  index into the function table. What that can get wrong is not the arithmetic
  — there is none — but WHICH index, and it goes wrong in the way a
  differential catches and a validator does not: a wrong index whose signature
  happens to match calls the wrong function and validates perfectly. (A wrong
  index with a DIFFERENT signature traps, because call_indirect checks the type
  at run time — the one guarantee this target gets for free where a register
  target buys it with a convention.)

    CallDouble  a procvar in a global, assigned then called.
    Pick        two procvars of the same signature chosen at run time, so the
                index has to come from the VALUE and not from anything static.
    Apply       a procvar passed AS an argument and called by the callee: the
                index crosses a call boundary as data.
    SumApplied  two different functions through the same parameter in one
                expression.
    IsAssigned  a NIL procvar. Table slot 0 is never handed out and never
                written, so it is null and a call through it traps — the right
                answer, and the reason a nil procvar needs no explicit check.
                Tested through Assigned rather than by calling, because a trap
                is not a value a differential can compare.

  VIRTUAL DISPATCH IS NOT HERE. It lives in virtual_slice.pas, which cannot be
  RUN yet: every class instantiation is a heap allocation and the heap is a
  later phase. That slice still compiles and validates, which proves the VMT
  path emits and type-checks; it does not prove it dispatches. }
program CallsSlice;

type
  TIntFn = function(x: Integer): Integer;

var
  Fn: TIntFn;

function Double_(x: Integer): Integer;
begin Double_ := x * 2; end;

function Triple(x: Integer): Integer;
begin Triple := x * 3; end;

function Apply(f: TIntFn; x: Integer): Integer;
begin Apply := f(x); end;

function CallDouble(x: Integer): Integer;
begin
  Fn := @Double_;
  CallDouble := Fn(x);
end;

function CallTriple(x: Integer): Integer;
begin
  Fn := @Triple;
  CallTriple := Fn(x);
end;

function Pick(which, x: Integer): Integer;
var g: TIntFn;
begin
  if which = 0 then g := @Double_ else g := @Triple;
  Pick := g(x);
end;

function SumApplied(x: Integer): Integer;
begin SumApplied := Apply(@Double_, x) + Apply(@Triple, x); end;

function IsAssigned(which: Integer): Integer;
var g: TIntFn;
begin
  g := nil;
  if which <> 0 then g := @Double_;
  if Assigned(g) then IsAssigned := 1 else IsAssigned := 0;
end;

{$ifndef WASM_NOMAIN}
begin
  writeln(CallDouble(21));
  writeln(CallTriple(21));
  writeln(Pick(0, 10));
  writeln(Pick(1, 10));
  writeln(SumApplied(10));
  writeln(IsAssigned(0));
  writeln(IsAssigned(1));
end.
{$else}
begin
end.
{$endif}

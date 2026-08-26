{ `TFn(p)(args)` -- calling straight through a procedural-type cast -- was
  `unexpected token`, while `f := TFn(p); f(args)` compiled and ran. The
  capability was entirely present; only the direct spelling was refused, and the
  diagnostic landed on the CALL line rather than the cast, so it read as a
  problem with the argument list. It is the natural way to dispatch through a
  hand-built VMT, which is how rtl-generics reaches its comparers.

  The ticket was parked on a design question -- "count the cast paths and decide
  whether they should be one, do not add a fifth `(`-handler". The count is ONE:
  a procedural type is always user-DECLARED, therefore always a type ALIAS, so
  the alias cast is the only flavour that can ever produce a callable. The
  builtin scalar names, the PChar adapter, enums and `string` cannot. (`^`,
  `.field` and `[i]` after a cast already worked; `(` was the only postfix
  missing.)

  Every row is `fpc -O1 -Mobjfpc` 3.2.2's.
  bug-p-cannot-call-directly-through-a-procedural-type-cast }
program test_call_through_a_procedural_cast;

type
  TFn     = function(x: LongInt): LongInt;
  TProc0  = procedure;
  TMethFn = function(x: LongInt): LongInt of object;
  TRec    = record F: Pointer; end;

  TOwner = class
    Bias: LongInt;
    function Add(x: LongInt): LongInt;
  end;

var
  sideEffect: LongInt;

function Twice(x: LongInt): LongInt;
begin Twice := x * 2; end;

procedure Bump;
begin sideEffect := sideEffect + 1; end;

function TOwner.Add(x: LongInt): LongInt;
begin Add := x + Bias; end;

var
  p: Pointer;
  f: TFn;
  V: TRec;
  o: TOwner;
  m: TMethFn;
  arr: array[0..1] of Pointer;

begin
  sideEffect := 0;
  p := @Twice;
  V.F := @Twice;
  arr[0] := @Twice; arr[1] := @Twice;

  { the control: cast into a variable, then call }
  f := TFn(p);
  writeln(f(21));

  { the spelling that was refused, over every receiver shape the cast can take }
  writeln(TFn(p)(21));
  writeln(TFn(V.F)(21));
  writeln(TFn(arr[1])(21));
  writeln(TFn(@Twice)(21));

  { nested: the result of one direct cast-call feeding another }
  writeln(TFn(p)(TFn(p)(5)));

  { a PROCEDURE (no result) through a cast, as a statement }
  TProc0(@Bump)();
  TProc0(@Bump)();
  writeln(sideEffect);

  { a METHOD POINTER, which is a 16-byte {Code, Data} record rather than a
    pointer -- the cast is a retype, not a reinterpret }
  o := TOwner.Create;
  o.Bias := 100;
  m := @o.Add;
  writeln(m(5));
  writeln(TMethFn(m)(5));
end.

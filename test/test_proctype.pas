program TestProcType;
{ Procedural types: calling through a proc-typed variable/param with arguments.
  Covers procedure & function pointers, statement & expression calls, multiple
  args, return values, and proc-typed globals/locals/params. }

type
  TIntProc = procedure(x: Integer);
  TBinOp   = function(a, b: Integer): Integer;
  TEntry   = procedure(arg: Pointer);

var
  op: TBinOp;
  gEntry: TEntry;
  gArg: Pointer;

procedure Hello(x: Integer);
begin
  writeln('hello ', x);
end;

function Add(a, b: Integer): Integer;
begin Add := a + b; end;

function Mul(a, b: Integer): Integer;
begin Mul := a * b; end;

procedure Greet(arg: Pointer);
begin
  writeln('greet ', Int64(arg));
end;

{ Call a proc-typed parameter directly. }
procedure CallIt(p: TIntProc; v: Integer);
begin
  p(v);
end;

{ The async CoStart shape: read a global proc-var into a local and call it. }
procedure RunEntry;
var e: TEntry; a: Pointer;
begin
  e := gEntry;
  a := gArg;
  e(a);
end;

var
  hp: TIntProc;
  r: Integer;
begin
  { statement call through a local proc-var }
  hp := @Hello;
  hp(1);

  { function pointer: expression call with return value }
  op := @Add;
  r := op(3, 4);
  writeln('add ', r);
  op := @Mul;
  writeln('mul ', op(5, 6));

  { proc-var inside a boolean expression }
  if op(2, 2) = 4 then writeln('expr ok');

  { proc-typed parameter }
  CallIt(@Hello, 7);

  { global proc-var read into a local (CoStart pattern) }
  gEntry := @Greet;
  gArg := Pointer(99);
  RunEntry;
end.

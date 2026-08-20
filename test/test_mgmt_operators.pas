program test_mgmt_operators;
{ `class operator Initialize/Finalize` — FPC's MANAGEMENT operators: the compiler
  invokes them at a variable's LIFETIME events, not from a call site. pxx
  desugars them into `Initialize(v); try BODY finally Finalize(v); end` around
  the declaring routine's body (and around the main body, for globals), which is
  why Exit and an exception both still finalize.

  Every line below is FPC 3.2.2's own output, byte for byte, with exactly two
  deliberate divergences — both measured, both recorded in
  feature-pascal-class-management-operators:

   1. the two trailing `fin` lines. FPC initializes a record-typed GLOBAL and
      then never finalizes it; pxx (and Delphi) do. A Finalize that never runs
      is a leak by construction, so this is one FPC line missing rather than
      one of ours too many.
   2. the `Mk` block. FPC materialises a returned record in a hidden temp in
      the CALLER and manages that temp too, so it prints an extra init/fin
      pair around the call. A compiler temporary is not a user lifetime; pxx
      has no such temp and emits neither.

  What the `Mk` block DOES pin down is shared with FPC: the function's own
  Result slot is not initialized on entry.

  Not exercised because pxx refuses them outright rather than silently skipping
  them: an array of a managed record, and a record or class with a managed
  record FIELD — feature-pascal-management-operators-nested-and-array. }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
uses SysUtils;

type
  { Both operators. }
  TFoo = record
    n: Integer;
    class operator Initialize(var a: TFoo);
    class operator Finalize(var a: TFoo);
  end;
  { Initialize only — a Finalize is not required to declare one. }
  TIOnly = record
    n: Integer;
    class operator Initialize(var a: TIOnly);
  end;
  { ...and Finalize only. }
  TFOnly = record
    n: Integer;
    class operator Finalize(var a: TFOnly);
  end;
  { A managed local inside a METHOD is an ordinary local. }
  TThing = class
    procedure Run;
  end;

class operator TFoo.Initialize(var a: TFoo);
begin writeln('  init'); a.n := 0; end;
class operator TFoo.Finalize(var a: TFoo);
begin writeln('  fin ', a.n); end;

class operator TIOnly.Initialize(var a: TIOnly);
begin writeln('  ionly init'); a.n := 0; end;

class operator TFOnly.Finalize(var a: TFOnly);
begin writeln('  fonly fin ', a.n); end;

procedure TThing.Run;
var x: TFoo;
begin
  writeln('  in method');
  x.n := 42;
end;

{ Two locals: BOTH lists run in DECLARATION order — `fin 1` before `fin 2`, not
  the reverse a stack discipline would suggest. Measured, not assumed. }
procedure TwoLocals;
var x, y: TFoo;
begin
  x.n := 1; y.n := 2;
  writeln('  body');
end;

{ Exit leaves through the finally arm. }
procedure EarlyExit;
var x: TFoo;
begin
  x.n := 4;
  if x.n = 4 then Exit;
  writeln('  NOT REACHED');
end;

{ ...and so does a raise. }
procedure Raiser;
var x: TFoo;
begin
  x.n := 6;
  raise Exception.Create('boom');
end;

{ A local is a ROUTINE-scoped slot, so the loop body does not re-initialize it. }
procedure LoopLocal;
var i: Integer; x: TFoo;
begin
  for i := 1 to 3 do x.n := i;
end;

{ A function's Result slot is NOT initialized — FPC does not either, so a
  single `init` (r's) precedes `in Mk` here. Called from a routine rather than
  the main body so that FPC's own caller-side temp is a routine local rather
  than a fourth startup global; see divergence 2 in the header. }
function Mk: TFoo;
begin
  writeln('  in Mk');
  Result.n := 9;
end;

procedure UseMk;
var r: TFoo;
begin
  r.n := Mk.n;
  writeln('  r.n=', r.n);
end;

procedure InitOnly;
var a: TIOnly;
begin
  a.n := 11;
  writeln('  ionly body ', a.n);
end;

procedure FinOnly;
var b: TFOnly;
begin
  b.n := 12;
  writeln('  fonly body');
end;

procedure Outer;
  procedure Inner;
  var z: TFoo;
  begin
    z.n := 5;
    writeln('  inner');
  end;
begin
  writeln('  outer');
  Inner;
end;

var
  g1: TFoo;
  g2: TFoo;
  th: TThing;
begin
  writeln('main start, g1.n=', g1.n, ' g2.n=', g2.n);

  writeln('TwoLocals');   TwoLocals;
  writeln('EarlyExit');   EarlyExit;
  writeln('Raiser');
  try Raiser; except writeln('  caught'); end;
  writeln('LoopLocal');   LoopLocal;
  writeln('InitOnly');    InitOnly;
  writeln('FinOnly');     FinOnly;
  writeln('Outer');       Outer;

  writeln('Method');
  th := TThing.Create;
  th.Run;
  th.Free;

  writeln('Mk');          UseMk;

  { g1 = 0 (its Initialize zeroed it), g2 set here so the two finalizers are
    told apart by their value. }
  g2.n := 77;
  writeln('main end');
end.

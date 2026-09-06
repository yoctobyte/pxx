program test_routine_local_specialization;
{ A `specialize` in a ROUTINE-LOCAL `type` section. The section is parsed by
  ParseSubroutine's declaration loop, which runs during the BODY pass -- so the
  specialization splice happens with Pass2Active true and must move the pass-2
  spans with it. It did not, and the symptom was never at the splice: the driver
  re-entered the program body N tokens early and reported `undefined variable
  (Result)` against a correct `begin`.
  bug-p-a-specialization-in-a-routine-local-type-section-desyncs-the-parse

  Every row below is aimed at one of the indices the splice moves, because they
  fail separately:
    1-2  the routine's own body, after the splice        (its DeclItemEnd)
    3    a routine declared AFTER the offending one      (its DeclItemStart)
    4-5  a specialization inside a NESTED routine's type section
    6    two splices in one routine, so the shift compounds
    7    the main program body itself                    (Pass2BodyTok)
  Sizes are the probe rather than a flag, so a row cannot pass by nothing
  happening: 4 and 6 are deliberately different widths from every other TRec
  in the file, and none of them is SizeOf(Integer). }
{$mode objfpc}

type
  generic TBox<T> = record
    f: T;
  end;

  TWide = record a, b, c, d: LongInt; end;   { 16 }

function LocalSpec: Integer;
type
  TBoxWord = specialize TBox<Word>;
var
  b: TBoxWord;
begin
  b.f := 7;
  LocalSpec := SizeOf(b.f) * 100 + b.f;      { 2 -> 207 }
end;

function AfterTheSplice: Integer;
{ No specialization of its own. Its DeclItemStart sits past LocalSpec's splice,
  so a splice that does not move the spans replays this routine from the wrong
  token. }
var
  w: TWide;
begin
  w.a := 3;
  AfterTheSplice := SizeOf(w) + w.a;         { 19 }
end;

function Scoped: Integer;
{ A specialization in a NESTED routine's local type section: a second splice,
  one nesting level deeper, in the same body pass.

  THE TWO TYPE NAMES ARE DELIBERATELY DIFFERENT and this row would be a better
  test if they were not. `TRec` in both scopes is what tgeneric94 writes, and
  pxx gets it wrong for a reason that has nothing to do with this splice: a
  nested routine's local type does not shadow the enclosing routine's, so the
  inner `SizeOf(TRec)` answers 3 where FPC says 1 -- with no generics anywhere.
  bug-p-a-nested-routines-local-type-does-not-shadow-the-enclosing-routines
  Naming them apart keeps this fixture measuring the splice; the shadowing bug
  carries its own repro rather than riding in here where a future reader would
  read its red as this one's. }
type
  TOuterRec = packed record p, q, r: Byte; end;   { 3 }
  TBoxOuter = specialize TBox<TOuterRec>;
var
  outer: TBoxOuter;

  function Inner: Integer;
  type
    TInnerRec = packed record s: Byte; end;       { 1 }
    TBoxInner = specialize TBox<TInnerRec>;
  var
    ib: TBoxInner;
  begin
    Inner := SizeOf(ib.f);                        { 1, not 3 }
  end;

begin
  Scoped := SizeOf(outer.f) * 10 + Inner;         { 31 }
end;

function TwoSplices: Integer;
type
  TBoxA = specialize TBox<LongInt>;
  TBoxB = specialize TBox<TWide>;
var
  x: TBoxA;
  y: TBoxB;
begin
  TwoSplices := SizeOf(x.f) + SizeOf(y.f);   { 4 + 16 = 20 }
end;

var
  n: Integer;
begin
  Writeln(LocalSpec);
  Writeln(AfterTheSplice);
  Writeln(Scoped);
  Writeln(TwoSplices);
  { The main body must still be entered at its own `begin`. Before the fix
    Pass2BodyTok was short by the splice width and the body started inside a
    routine, so a plain statement here is the assertion. }
  n := 0;
  n := n + LocalSpec;
  Writeln(n);
end.

{ A nested routine is LIFTED to top level and its header is read a second time
  there, with CurProc = -1 -- so a signature naming one of the enclosing
  routine's local types resolved on the first reading and answered
  `unknown type` on the second, reported inside the appended builtin unit
  because that is where the re-parse lands. The BODY was never affected (its
  CurProc is the lifted routine, whose ProcLexParent already reaches outward),
  which is why this hid: every probe that put the local type in a `var` passed.

  Row 3 is the one that cannot pass by accident: the two enclosing routines
  declare DIFFERENT records under the same spelling, so a fix that made the
  header resolve globally rather than in the writing routine's scope would give
  both nested routines the same one and print the wrong pair.

  Expected values are the fpc 3.2.2 oracle.
  bug-p-a-lifted-nested-routines-signature-cannot-see-the-enclosing-routines-local-type }
program test_a_lifted_nested_routines_signature_sees_the_enclosing_local_type;

{ 1. parameter type }
procedure ParamRow;
type TR = record F: LongInt; end;
var r: TR;
  function Get(const x: TR): LongInt;
  begin Get := x.F; end;
begin
  r.F := 11;
  writeln('param ', Get(r));
end;

{ 2. RESULT type -- the other half of the header, and a separate code path }
procedure ResultRow;
type TR = record F: LongInt; end;
var r: TR;
  function Make(v: LongInt): TR;
  begin Make.F := v * 2; end;
begin
  r := Make(11);
  writeln('result ', r.F);
end;

{ 3. two routines, one spelling, two records -- innermost must win per routine }
procedure ShadowA;
type TR = record F: LongInt; end;
var r: TR;
  function Show(const x: TR): LongInt;
  begin Show := x.F; end;
begin
  r.F := 33;
  writeln('shadow-a ', Show(r));
end;

procedure ShadowB;
type TR = record S: ShortString; end;
var r: TR;
  function Show(const x: TR): ShortString;
  begin Show := x.S; end;
begin
  r.S := 'bee';
  writeln('shadow-b ', Show(r));
end;

{ 4. an enclosing local ALIAS, not a record -- a different table with the same
     routine-scope column }
procedure AliasRow;
type TMyInt = LongInt;
  function Twice(v: TMyInt): TMyInt;
  begin Twice := v + v; end;
begin
  writeln('alias ', Twice(22));
end;

{ 5. two levels: the inner routine is lifted out of a routine that is itself
     lifted, so the scope walk has to keep going outward }
procedure TwoDeep;
type TR = record F: LongInt; end;
var r: TR;
  procedure Middle(const x: TR);
    function Inner(const y: TR): LongInt;
    begin Inner := y.F + 1; end;
  begin
    writeln('two-deep ', Inner(x));
  end;
begin
  r.F := 54;
  Middle(r);
end;

begin
  ParamRow;
  ResultRow;
  ShadowA;
  ShadowB;
  AliasRow;
  TwoDeep;
end.

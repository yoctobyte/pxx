program test_a_procedural_types_parameter_carries_its_default_through_every_indirect_call_shape;
{ A default value declared on a PROCEDURAL TYPE's parameter, and every shape
  that can omit it.

  `ParseProcTypeSignature` was the one of the four parameter parsers in
  pasparser_decl.inc with no `ParseParamDefaultValue` call at all, so
  `TCb = procedure(n: Integer = 5)` was `expected ')' before '='` for EVERY
  parameter type while the identical routine, method and interface-method
  declarations compiled.

  THE PARSE IS THE SMALL HALF AND IT IS NOT THE BUG'S END. A default that is
  RECORDED and never FILLED is the shape that segfaulted at four interface arms
  (bug-p-an-interface-dispatched-call-that-omits-a-defaulted-argument-segfaults):
  the arity check accepts the short call *because* the parameter has a default,
  and then nothing supplies it. So two call paths had to learn to fill:
  BuildIndirectCallAST for `c(1)`, and the statement path's parenless arm for
  `c;` -- whose guard was `ParamCount = 0`, which is the degenerate case of
  "nothing left to supply" rather than a separate rule.

  VALUE KINDS ARE ROWS, not padding: the row-write copies ProcParamDefaultVal,
  DefaultIsStr, DefaultIsFloat, DefaultIsSet, DefaultSOff and DefaultSLen as
  separate columns, so an Integer-only fixture proves one of six. A string
  default that arrives empty and a set default that arrives {} are both
  plausible values, not crashes.

  THE CONTROLS ARE THE POINT OF THE LAST TWO ROWS. `NoDef` must still refuse a
  short call -- if it did not, the fill would be happening for every proc type
  and the rows above would pass for the wrong reason. And an explicitly passed
  argument must still win over the default, which is the row that fails if the
  fill runs unconditionally instead of only for the missing tail.

  ONE ROW IS OURS AND FPC REFUSES IT, deliberately: `procedure TakesCb(cb:
  procedure(n: Integer = 5))` -- an ANONYMOUS procedural type in a parameter
  position -- is `Type identifier expected` under fpc 3.2.2, which only accepts
  the spelling through a named alias. Us accepting what FPC rejects is not a
  defect, so the row stays; the fpc cross-check was run on a copy with a named
  alias in that one place and matched all eleven rows byte for byte.

  `parenless meth` looks like padding beside `parenless int` and is not. While
  the statement path's parenless arm was being split, its method-pointer flag
  (`ASTSLen := 1` for a {Code,Data} pair) was lost for one build, and this is
  the ONLY row that saw it: M-1480588942 instead of M11, with the other ten
  green. A method pointer and a bare code pointer differ in the lowering, not in
  the default. The other ten rows were not weak -- they were correct controls
  for a different question: every one of them asserts the DEFAULT-VALUE
  machinery, and what broke was the {Code,Data} pair underneath it. So when an
  arm is split, the rows to re-read are not the ones about the feature, they are
  the ones about the SHAPE the arm produces; here a flag was lost, and exactly
  one row asserted the flag. `M-1480588942` was loud enough to see. The same
  slip in a row whose Data half held something printable would have been a
  plausible wrong value on eleven greens. (frankS's framing.)

  bug-p-a-procedural-types-parameter-cannot-carry-a-default-value }
{$mode objfpc}{$H+}

type
  TColour = (cRed, cGreen, cBlue);
  TColours = set of TColour;

  TCbInt   = procedure(n: Integer = 5);
  TCbTwo   = procedure(a: Integer; b: Integer = 7);
  TCbStr   = procedure(const s: AnsiString = 'dflt');
  TCbFloat = procedure(d: Double = 2.5);
  TCbSet   = procedure(c: TColours = [cRed, cBlue]);
  TCbMeth  = procedure(n: Integer = 11) of object;

  TObj = class
    procedure M(n: Integer = 11);
  end;

var Fail: Integer;

procedure Row(const nm, got, want: AnsiString);
begin
  WriteLn(nm, ' ', got);
  if got <> want then begin WriteLn('  MISMATCH: wanted ', want); Inc(Fail); end;
end;

var Seen: AnsiString;

function IStr(n: Integer): AnsiString;
begin
  Str(n:0, Result);
end;


procedure PInt(n: Integer = 5);            begin Seen := IStr(n); end;
procedure PTwo(a: Integer; b: Integer = 7); begin Seen := IStr(a) + ':' + IStr(b); end;
procedure PStr(const s: AnsiString = 'dflt'); begin Seen := s; end;
procedure PFloat(d: Double = 2.5);         begin Str(d:0:2, Seen); end;
procedure PSet(c: TColours = [cRed, cBlue]);
begin
  Seen := '';
  if cRed   in c then Seen := Seen + 'R';
  if cGreen in c then Seen := Seen + 'G';
  if cBlue  in c then Seen := Seen + 'B';
end;
procedure TObj.M(n: Integer = 11);         begin Seen := 'M' + IStr(n); end;

{ An ANONYMOUS procedural type in a parameter position — the spelling that
  reaches ParseProcTypeSignature without a named alias in front of it. }
procedure TakesCb(cb: procedure(n: Integer = 5));
begin
  cb;
end;

var
  ci: TCbInt; ct: TCbTwo; cs: TCbStr; cf: TCbFloat; cx: TCbSet;
  cm: TCbMeth; o: TObj;
begin
  Fail := 0;
  ci := @PInt; ct := @PTwo; cs := @PStr; cf := @PFloat; cx := @PSet;
  o := TObj.Create; cm := @o.M;

  Seen := ''; ci;        Row('parenless int  ', Seen, '5');
  Seen := ''; ci(9);     Row('explicit int   ', Seen, '9');
  Seen := ''; ct(1);     Row('short two-arg  ', Seen, '1:7');
  Seen := ''; ct(1, 2);  Row('full two-arg   ', Seen, '1:2');
  Seen := ''; cs;        Row('parenless str  ', Seen, 'dflt');
  Seen := ''; cs('x');   Row('explicit str   ', Seen, 'x');
  Seen := ''; cf;        Row('parenless float', Seen, '2.50');
  Seen := ''; cx;        Row('parenless set  ', Seen, 'RB');

  { a METHOD POINTER: {Code,Data}, a different lowering from a bare code pointer }
  Seen := ''; cm;        Row('parenless meth ', Seen, 'M11');
  Seen := ''; cm(4);     Row('explicit meth  ', Seen, 'M4');

  { an ANONYMOUS proc type in a parameter position }
  Seen := ''; TakesCb(@PInt); Row('anon param     ', Seen, '5');

  if Fail = 0 then WriteLn('PROCTYPEDEFAULT OK')
  else WriteLn('PROCTYPEDEFAULT FAILED ', Fail);
end.

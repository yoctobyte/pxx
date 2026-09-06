{ `CurTokenText[1]` inside a method — a BARE call to the class's own
  parameterless method, indexed — dropped its `[`. In an expression it died as
  `expected ')' before '['`; in a statement as `a statement cannot start with
  '['`. Neither diagnostic mentions a return type, which is what the defect was.

  THE ARM HAD ITS OWN TWO-MEMBER RETURN-TYPE LIST: the implicit-Self dispatch in
  pasparser_expr.inc applied a trailing selector only when the method returned
  tyClass or tyRecord. Every other kind fell through with the `[` unconsumed.
  Every other route to the same call already reached
  ApplyCallResultPtrSuffix — pasparser_lval.inc's "ONE materialisation point for
  a suffix on a call RESULT" — which handles `.`, `[`, `^` and `(` across
  strings, arrays, pointers and metaclasses. The fix is the arm joining that
  funnel, not a third member on the list.

  THE THREE CONTROLS ARE THE SPELLINGS THAT ALREADY WORKED, AND THEY WERE
  MEASURED AT THE UNFIXED BINARY, not assumed: `Self.T[1]`, `p.T[1]` from
  outside, and a bare GLOBAL function `GT[1]` all indexed correctly before this
  change. That is the whole reason the bug was findable — one spelling out of
  four behaving differently is what an enumerated list looks like from outside.
  If any control moves, the arm was rerouted wrongly rather than merely widened.

  EVERY ROW ASSERTS A CHARACTER OR A VALUE, never that it compiled. A dropped
  suffix is a PARSE failure today, but the funnel it now enters can also
  silently index the wrong thing, and "it compiles" cannot tell those apart.
  The dynamic-array and class-result rows are here because they are the kinds
  either side of the old list: `dyn` was excluded and must now work, `cls` was
  included and must not move.

  fcl-passrc pparser.pp:2468, `if not (length(CurTokenText)=1) or not
  (CurTokenText[1] in ['A'..'_'])`. bug-p-indexing-the-result-of-a-bare-implicit-self-method-call }
{$mode objfpc}
program test_indexing_a_bare_implicit_self_method_result;
type
  TIntArrayStub = array of Integer;
  TInner = class
    N: Integer;
  end;
  TP = class
    FI: TInner;
    constructor Create;
    function Txt: String;                  { the fcl-passrc shape: String result }
    function Dyn: TIntArrayStub;
    function Cls: TInner;
    function BareExpr: Char;
    function SelfQualified: Char;
    function InStatement: Char;
    function DynRow: Integer;
    function ClsRow: Integer;
    function SetTest: Boolean;
  end;

function GT: String; begin GT := 'AZ'; end;

constructor TP.Create;
begin
  FI := TInner.Create;
  FI.N := 77;
end;

function TP.Txt: String; begin Txt := 'AZ'; end;

function TP.Dyn: TIntArrayStub;
begin
  SetLength(Dyn, 3);
  Dyn[0] := 10; Dyn[1] := 20; Dyn[2] := 30;
end;

function TP.Cls: TInner; begin Cls := FI; end;

{ THE FIX: a bare implicit-Self call, indexed, in an EXPRESSION }
function TP.BareExpr: Char;
begin
  BareExpr := Txt[2];
end;

{ CONTROL 1: the same call through Self., which already worked }
function TP.SelfQualified: Char;
begin
  SelfQualified := Self.Txt[2];
end;

{ THE FIX, second context: a bare implicit-Self call, indexed, in a STATEMENT }
function TP.InStatement: Char;
var c: Char;
begin
  c := Txt[1];
  InStatement := c;
end;

{ the kind the old list EXCLUDED }
function TP.DynRow: Integer;
begin
  DynRow := Dyn[1];
end;

{ the kind the old list INCLUDED — must not move }
function TP.ClsRow: Integer;
begin
  ClsRow := Cls.N;
end;

{ the exact fcl-passrc expression, indexed inside a set test }
function TP.SetTest: Boolean;
begin
  SetTest := not (length(Txt) = 2) or not (Txt[1] in ['A'..'_']);
end;

var
  p: TP;
begin
  p := TP.Create;
  WriteLn('bare expr  = ', p.BareExpr);
  WriteLn('bare stmt  = ', p.InStatement);
  WriteLn('set test   = ', p.SetTest);
  WriteLn('dyn result = ', p.DynRow);
  WriteLn('cls result = ', p.ClsRow);
  WriteLn('self qual  = ', p.SelfQualified);
  WriteLn('outside    = ', p.Txt[2]);
  WriteLn('global fn  = ', GT[1]);
end.

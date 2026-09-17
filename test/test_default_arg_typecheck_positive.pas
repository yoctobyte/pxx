{ Calls that OMIT a trailing defaulted argument and must keep working.

  The companion of test_default_arg_typecheck_fail.pas. That one pins the
  refusal; this one pins that the refusal is not wider than it should be --
  TryFillTrailingDefaults is a FALLBACK reached only after the ordinary match
  has refused, so anything its new type gate turns down becomes "no overload
  matches these arguments" and a rule narrower than the real one converts a
  working call into a diagnostic.

  THE PROCEDURAL AND nil ROWS ARE THE POINT, not the ordinary ones. The gate
  asks MatchParamAccepted, which reaches MatchArgProcAddrOk and MatchArgNilOk;
  with the argument side channels left INVALID both answer False and these two
  rows -- and nothing else here -- would be refused. They are what says the
  channels are actually being filled, and they fail differently from the rest.

  THE MULTI-ARGUMENT ROWS PUT THE INTERESTING ARGUMENT LAST (CLAUDE.md: where a
  construct takes an ordered list, the position of the interesting element is a
  variable). A gate that checked only argument 0 passes every one-argument row
  here and is caught by TwoThenDefault/ThreeThenDefault.

  Every expected value measured under fpc 3.2.2 with this same source. }
program test_default_arg_typecheck_positive;

type
  TCmp = function(a, b: Integer): Integer;
  TRec = record v: Integer; end;
  PRec = ^TRec;

var ok, total: Integer;

procedure Chk(cond: Boolean; const what: AnsiString);
begin
  Inc(total);
  if cond then Inc(ok) else WriteLn('FAIL: ', what);
end;

function Sub(a, b: Integer): Integer;
begin Sub := a - b; end;

{ one argument, one default }
function OneThenDefault(s: AnsiString; k: Integer = 7): Integer;
begin OneThenDefault := Length(s) + k; end;

{ the default is reached past TWO supplied arguments }
function TwoThenDefault(a: Integer; s: AnsiString; k: Integer = 7): Integer;
begin TwoThenDefault := a + Length(s) + k; end;

{ ...and past three, with the interesting one last again }
function ThreeThenDefault(a: Integer; b: Int64; s: AnsiString; k: Integer = 7): Integer;
begin ThreeThenDefault := a + Integer(b) + Length(s) + k; end;

{ a PROCEDURAL parameter: the shape that needs MatchArgProcAddrOk }
function CallsIt(f: TCmp; k: Integer = 7): Integer;
begin CallsIt := f(10, 3) + k; end;

{ a POINTER parameter: the shape that needs MatchArgNilOk }
function TakesPtr(p: PRec; k: Integer = 7): Integer;
begin
  if p = nil then TakesPtr := k else TakesPtr := p^.v + k;
end;

{ overloaded AND defaulted: the gate must not disturb which one wins }
function Pick(s: AnsiString; k: Integer = 7): Integer; overload;
begin Pick := 100 + k; end;
function Pick(n: Int64; k: Integer = 7): Integer; overload;
begin Pick := 200 + k; end;

var r: TRec;
begin
  ok := 0; total := 0;

  Chk(OneThenDefault('abc') = 10, 'one argument, default filled');
  Chk(OneThenDefault('abc', 1) = 4, 'one argument, default supplied');

  Chk(TwoThenDefault(5, 'abc') = 15, 'two arguments, default filled');
  Chk(ThreeThenDefault(5, 6, 'abc') = 21, 'three arguments, default filled');

  { a WIDENING conversion in the last checked position must still be accepted:
    the gate asks the union predicate, not exact match }
  Chk(ThreeThenDefault(5, 6, 'abc') = 21, 'Integer literal widens into Int64');

  Chk(CallsIt(@Sub) = 14, 'procedure ADDRESS with a default behind it');

  Chk(TakesPtr(nil) = 7, 'nil with a default behind it');
  r.v := 5;
  Chk(TakesPtr(@r) = 12, 'typed pointer with a default behind it');

  Chk(Pick('abc') = 107, 'overloaded+defaulted: the string arm');
  Chk(Pick(Int64(3)) = 207, 'overloaded+defaulted: the integer arm');

  WriteLn('total ok ', ok, ' / ', total);
end.

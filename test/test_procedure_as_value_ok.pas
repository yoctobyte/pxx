{ The three shapes the no-result-call check must NOT reject, pinned as a pair
  with test_procedure_as_value_fail.pas:

    - a CONSTRUCTOR as a value. It is registered with IsFunc=False (its keyword
      is neither `function` nor `procedure`), so it looks exactly like the
      rejected case and has to be exempted by name-independent means.
    - a `(`-led STATEMENT — `(o as T).M;` — which the parser handles with the
      expression parser even though it is a statement. This one regressed the
      as-inline-call probe case on the first attempt.
    - an ordinary procedure call as a statement, with and without arguments;
    - a void method on a FUNCTION RESULT as a statement — `GetThing.Bump;`.
      That one was missed on the first attempt and TRACK T caught it, not the
      local gate: gate.sh quick, gate.sh lib, 34 demos and the whole fpc probe
      were green with the false positive in place. It is here so the local pair
      covers it too. }
program test_procedure_as_value_ok;
type
  TBase = class
  end;
  TThing = class(TBase)
    n: Integer;
    constructor Create(k: Integer);
    procedure Bump;
    procedure Add(k: Integer);
    function Val: Integer;
  end;
constructor TThing.Create(k: Integer); begin n := k; end;
procedure TThing.Bump; begin n := n + 1; end;
procedure TThing.Add(k: Integer); begin n := n + k; end;
function TThing.Val: Integer; begin Result := n; end;
var t: TThing; b: TBase; total: Integer;

function GetThing: TThing;
begin
  Result := t;
end;

begin
  t := TThing.Create(10);        { constructor as a value }
  t.Bump;                        { procedure statement, no args }
  t.Add(5);                      { procedure statement, with args }
  b := t;
  (b as TThing).Bump;            { `(`-led statement through an as-cast }
  GetThing.Bump;                 { void method on a function result, statement }
  GetThing.Add(1);               { same, with arguments }
  { NOT tested here: a member read off a constructor RESULT
    (`TThing.Create(2).n`) silently yields garbage — a separate, pre-existing
    bug (bug-p-member-off-a-call-result-in-an-expression-yields-garbage). The
    constructor-as-a-value exemption this file exists to pin is already
    covered by the `t := TThing.Create(10)` above. }
  total := t.Val;
  writeln(total);
  if total = 19 then writeln('PASS') else writeln('FAIL');
end.

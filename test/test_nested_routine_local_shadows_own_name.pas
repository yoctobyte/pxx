program test_nested_routine_local_shadows_own_name;
{$mode objfpc}{$H+}

{ bug-p-a-const-named-like-its-nested-routine-binds-the-routine.

  A NESTED routine is lifted to top level under a mangled name (`Inner$13`), and
  the lifter rewrites every reference to the routine's own name in its body —
  those are the function-result variable and self-recursive calls. That rename
  ran BEFORE the check for the routine's own params and locals, so a declaration
  inside the routine that happened to share its name was rewritten too, and the
  body failed with `undefined variable (Inner$13)`.

  The ticket reported the CONST shape and listed the local-var shape as
  untested; measuring found var and parameter broken the same way, and only the
  `type` shape working (a type name is never an expression reference, so it
  never reaches the rename). Non-nested routines were always fine: the mangle is
  the one thing their path does not do.

  Every expected value here is `fpc -O- -Mobjfpc`'s own output.

  The controls at the end are the point of the fix's ordering: a function's
  RESULT variable is the routine name itself and is NOT a declared local, so it
  must still follow the mangle — as must a self-recursive call, including one
  that carries a captured variable. }

var
  okc, total: Integer;

procedure Chk(const nm: string; got, want: Integer);
begin
  Inc(total);
  if got = want then begin Inc(okc); WriteLn('ok ', nm); end
  else WriteLn('FAIL ', nm, ' got ', got, ' want ', want);
end;

{ ---- the three broken shapes: a declaration named like its own routine ---- }

procedure ConstShape;
var seen: Integer;
  procedure Inner;
  const inner: Integer = 0;          { same name as the routine }
  begin Inc(inner); seen := inner; end;
begin
  seen := -1;
  Inner; Chk('const-1st', seen, 1);
  Inner; Chk('const-2nd', seen, 2);   { a typed const keeps its value across calls }
end;

procedure VarShape;
var seen: Integer;
  procedure Inner;
  var inner: Integer;
  begin inner := 7; seen := inner; end;
begin seen := -1; Inner; Chk('var', seen, 7); end;

procedure ParamShape;
var seen: Integer;
  procedure Inner(inner: Integer);
  begin seen := inner * 2; end;
begin seen := -1; Inner(5); Chk('param', seen, 10); end;

procedure TypeShape;
var seen: Integer;
  procedure Inner;
  type inner = Integer;
  var v: inner;
  begin v := 9; seen := v; end;
begin seen := -1; Inner; Chk('type', seen, 9); end;

{ ---- and the same thing while the routine also CAPTURES an enclosing var,
       so the shadowed name and the capture machinery meet in one body ---- }

procedure ShadowAndCapture;
var acc: Integer;
  procedure Inner;
  var inner: Integer;
  begin inner := 3; acc := acc + inner; end;
begin acc := 100; Inner; Inner; Chk('shadow+capture', acc, 106); end;

{ ---- controls: the rename must STILL happen for the two things it is for ---- }

procedure ResultVarControl;
var seen: Integer;
  function Inner: Integer;
  begin Inner := 42; end;             { the routine name IS the result variable }
begin seen := Inner; Chk('result-var', seen, 42); end;

procedure RecursionControl;
var calls: Integer;
  function Fact(n: Integer): Integer;
  begin
    calls := calls + 1;               { captured — the self-call must carry it }
    if n <= 1 then Fact := 1 else Fact := n * Fact(n - 1);
  end;
begin
  calls := 0;
  Chk('recursion', Fact(5), 120);
  Chk('recursion-captures', calls, 5);
end;

{ a local shadowing the name of a SIBLING nested routine must not be rewritten
  either — the lifter rewrites sibling call sites by name as well }
procedure SiblingShape;
var seen: Integer;
  procedure Helper;
  begin seen := 1; end;
  procedure User;
  var helper: Integer;
  begin helper := 5; seen := helper; end;
begin seen := -1; User; Chk('sibling-name', seen, 5); Helper; Chk('sibling-call', seen, 1); end;

begin
  okc := 0; total := 0;
  ConstShape;
  VarShape;
  ParamShape;
  TypeShape;
  ShadowAndCapture;
  ResultVarControl;
  RecursionControl;
  SiblingShape;
  WriteLn('total ok ', okc, ' / ', total);
end.

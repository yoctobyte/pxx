{ A parameterless overload is reachable without parentheses, whichever ORDER
  the set is declared in.

  FindProc returns the REPRESENTATIVE of a same-named set -- whichever member
  the hash chain reaches first -- and both parenless call doors used to test
  that one proc's arity and give up. So when the parameterful overload was
  declared first, `f` was "undefined variable (f)" in an expression and
  "wrong number of parameters in call to p -- called with none" as a statement,
  over names that are right there in scope, while `f()` and `p()` were fine.

  EVERY PAIR HERE IS DECLARED PARAMETERFUL-FIRST, WHICH IS THE ARRANGEMENT THAT
  LOSES. Declared the other way round every row below already passed on the
  unfixed compiler, so a fixture written the natural way certifies the bug
  instead of catching it -- CLAUDE.md, "the passing arrangements are not a
  sample, they are the population everyone writes". FPC's own globals.pas
  declares `getrealtime(const st: TSystemTime)` at 728 and `getrealtime` at
  729, in that order, which is how the FPC corpus hits this and no test did.
  The Ord* pair below is declared the WINNING way round on purpose, as the
  control that says order is no longer what decides.

  Both doors are asserted because they are one defect wearing two diagnostics:
  a grep for either message finds only half of it. }
program test_parenless_call_to_an_overloaded_name;

type
  TRec = record a: LongInt; end;

var
  ok, total: LongInt;
  Hits: LongInt;

procedure Chk(cond: Boolean; const what: string);
begin
  total := total + 1;
  if cond then ok := ok + 1
  else WriteLn('FAIL: ', what);
end;

{ --- functions: parameterful FIRST, parameterless SECOND ------------------- }
function Grt(const st: TRec): Real;
begin Grt := st.a * 1.0; end;

function Grt: Real;
begin Grt := 7.0; end;

{ --- procedures: same order, the statement door --------------------------- }
procedure Bump(const st: TRec);
begin Hits := Hits + st.a; end;

procedure Bump;
begin Hits := Hits + 100; end;

{ --- an all-DEFAULTED overload is parenless at the call site too ----------- }
function Dflt(const st: TRec): LongInt;
begin Dflt := st.a; end;

function Dflt(k: LongInt = 42): LongInt;
begin Dflt := k; end;

{ --- the CONTROL pair, declared the winning way round --------------------- }
function Ordr: LongInt;
begin Ordr := 5; end;

function Ordr(const st: TRec): LongInt;
begin Ordr := st.a; end;

{ --- a name with NO parenless member: the arity error must survive --------- }
function NeedsArg(const st: TRec): LongInt;
begin NeedsArg := st.a; end;

var
  r: TRec;
  h: Real;
  n: LongInt;
begin
  ok := 0; total := 0; Hits := 0;
  r.a := 3;

  { the expression door, bare }
  h := Grt;
  Chk(h = 7.0, 'bare Grt in an expression');
  h := Grt - 1.0;
  Chk(h = 6.0, 'bare Grt as an operand');
  h := Grt();
  Chk(h = 7.0, 'Grt() still works');
  h := Grt(r);
  Chk(h = 3.0, 'the parameterful overload still resolves');

  { nested and argument positions reach the same door }
  h := Grt + Grt;
  Chk(h = 14.0, 'bare Grt twice in one expression');
  n := Trunc(Grt);
  Chk(n = 7, 'bare Grt as a call argument');

  { the statement door, bare }
  Hits := 0;
  Bump;
  Chk(Hits = 100, 'bare Bump as a statement');
  Bump();
  Chk(Hits = 200, 'Bump() still works');
  Bump(r);
  Chk(Hits = 203, 'the parameterful procedure overload still resolves');

  { all-defaulted, parameterless AT THE CALL SITE }
  n := Dflt;
  Chk(n = 42, 'bare Dflt takes the all-defaulted overload');
  n := Dflt(9);
  Chk(n = 9, 'Dflt(9) fills nothing and passes 9');
  n := Dflt(r);
  Chk(n = 3, 'Dflt(r) still picks the record overload');

  { the control: declared parameterless-FIRST, must be unaffected }
  n := Ordr;
  Chk(n = 5, 'bare Ordr, declared parameterless-first');
  n := Ordr(r);
  Chk(n = 3, 'Ordr(r) picks the record overload');

  { a name whose set has no parenless member is still an arity error, and that
    is the positive control: without it every row above passes if the doors
    were simply made to accept anything. Asserted by the Makefile row, which
    compiles the negative fixture separately -- see test_parenless_call_*.sh. }
  n := NeedsArg(r);
  Chk(n = 3, 'NeedsArg(r) with its argument');

  WriteLn('total ok ', ok, ' / ', total);
end.

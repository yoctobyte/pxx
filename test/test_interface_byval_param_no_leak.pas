{ A COM interface passed BY VALUE leaked one reference per call.

  The caller materialises a private temp for a by-value interface argument, and
  that temp is ONE stack slot reused by every execution of the call site. It was
  filled with a raw copy_rec and then retained -- so each call OVERWROTE the
  previous occupant without releasing it, and the reference went on the floor:

    for i := 1 to 5 do
    begin
      f := TFoo.Create;
      TakeVal(f);        { by-value interface param }
      f := nil;
    end;
                         { pinned: 5 constructed, 1 destructed  FPC: 5 / 5 }

  and from the MAIN body, where there is no scope exit to release even the LAST
  occupant, the pinned binary ran ZERO destructors for five objects.

  `const` and `var` interface parameters were always correct -- they stay by-ref
  aliases of the caller's slot with no copy and no refcount -- which is what hid
  this: two of the three parameter modes were right.

  The fix uses PXXIntfAssign (retain source, release old dest, copy) instead of
  hand-rolling the halves, and records a main-body temp for the program-exit
  release pass the way an as-cast temp already was.

  NOTE ON TIMING (was a divergence, fixed 2026-08-21): pxx used to release the
  temp at the CALLER's scope exit where FPC releases it at CALLEE return, so the
  last object of a batch died later -- which is why the Run() counts below are
  checked AFTER the owning routine returns rather than inside it. The temp is
  now released at the end of the STATEMENT containing the call, and the timing
  block near the bottom checks the counts INSIDE the routine, which is what the
  old model could not satisfy.
  bug-a-a-by-value-interface-param-is-released-at-caller-scope-exit.

  Every expectation is `fpc -O- -Mobjfpc` 3.2.2's.
  bug-a-an-interface-passed-by-value-leaks-a-reference-per-call }
program test_interface_byval_param_no_leak;
{$mode objfpc}{$H+}

type
  IFoo = interface
    ['{11111111-1111-1111-1111-111111111111}']
    procedure Bump;
  end;
  TFoo = class(TInterfacedObject, IFoo)
    procedure Bump;
    destructor Destroy; override;
  end;

var
  created, destroyed, pass, fail: Integer;
  mf: IFoo;   { main-body by-value argument source — see the timing block }

procedure TFoo.Bump; begin end;
destructor TFoo.Destroy; begin Inc(destroyed); inherited Destroy; end;

procedure Chk(const what: string; got, want: Integer);
begin
  if got = want then
  begin
    Inc(pass);
    writeln('ok   ', what, ' = ', got);
  end
  else
  begin
    Inc(fail);
    writeln('FAIL ', what, ' = ', got, ' want ', want);
  end;
end;

procedure TakeVal(a: IFoo);   begin a.Bump; end;
procedure TakeConst(const a: IFoo); begin a.Bump; end;
procedure TakeVar(var a: IFoo);     begin a.Bump; end;
procedure TakeTwo(a, b: IFoo);      begin a.Bump; b.Bump; end;

{ Each driver runs its loop and RETURNS, so the caller-scope release of the
  argument temp has happened by the time the count is checked. }

procedure LoopVal(n: Integer);
var i: Integer; f: IFoo;
begin
  for i := 1 to n do
  begin
    f := TFoo.Create; Inc(created);
    TakeVal(f);
    f := nil;
  end;
end;

procedure LoopConst(n: Integer);
var i: Integer; f: IFoo;
begin
  for i := 1 to n do
  begin
    f := TFoo.Create; Inc(created);
    TakeConst(f);
    f := nil;
  end;
end;

procedure LoopVar(n: Integer);
var i: Integer; f: IFoo;
begin
  for i := 1 to n do
  begin
    f := TFoo.Create; Inc(created);
    TakeVar(f);
    f := nil;
  end;
end;

{ the SAME reference in both parameters: the retain-before-release order inside
  PXXIntfAssign is what keeps this from destroying the object mid-call }
procedure LoopTwo(n: Integer);
var i: Integer; f: IFoo;
begin
  for i := 1 to n do
  begin
    f := TFoo.Create; Inc(created);
    TakeTwo(f, f);
    f := nil;
  end;
end;

{ nested call sites: an inner by-value call inside an outer one }
procedure Inner(a: IFoo); begin TakeVal(a); end;
procedure LoopNested(n: Integer);
var i: Integer; f: IFoo;
begin
  for i := 1 to n do
  begin
    f := TFoo.Create; Inc(created);
    Inner(f);
    f := nil;
  end;
end;

{ a single call, no loop -- the shape that always worked, kept as a canary }
procedure OneCall;
var f: IFoo;
begin
  f := TFoo.Create; Inc(created);
  TakeVal(f);
  f := nil;
end;

{ ---- TIMING, checked INSIDE the routine ----------------------------------

  The header note above used to say the counts are checked AFTER the owning
  routine returns, because pxx released the argument temp at the CALLER's scope
  exit while FPC releases it at callee return. That is fixed: the temp is
  released at the end of the STATEMENT containing the call, so by the next
  statement the object's only reference is the caller's own variable and
  `f := nil` destroys it -- FPC's moment.

  These cases would all have failed under the old model, and the main-body one
  most of all: a main-body temp was held to PROGRAM EXIT.
  bug-a-a-by-value-interface-param-is-released-at-caller-scope-exit }

procedure TimingVal;
var f: IFoo;
begin
  created := 0; destroyed := 0;
  f := TFoo.Create; Inc(created);
  TakeVal(f);
  Chk('timing: alive right after the call', destroyed, 0);
  f := nil;
  Chk('timing: dead at f := nil, not at scope exit', destroyed, 1);
end;

procedure TimingTwoSameRef;
var f: IFoo;
begin
  created := 0; destroyed := 0;
  f := TFoo.Create; Inc(created);
  TakeTwo(f, f);
  Chk('timing: two same-ref args, alive after the call', destroyed, 0);
  f := nil;
  Chk('timing: two same-ref args, dead at f := nil', destroyed, 1);
end;

{ A nested call site: the inner call's temp and the outer call's temp are
  released at the same statement boundary, not one of them mid-expression.

  Note what this case does NOT show. `f := nil` does not destroy, in FPC either:
  PassThrough's FUNCTION RESULT is a separate temp that both compilers keep to
  the routine's scope exit, and it is still holding a reference. The argument
  temps being released on time is visible in the count staying at 0 through a
  nested statement rather than in an early destroy. Expectation checked by
  running this file under FPC 3.2.2, not by reasoning about it -- the first
  version of this case asserted 1 and FPC failed it too. }
function PassThrough(a: IFoo): IFoo;
begin
  a.Bump; Result := a;
end;

procedure TimingNested;
var f: IFoo;
begin
  created := 0; destroyed := 0;
  f := TFoo.Create; Inc(created);
  TakeVal(PassThrough(f));
  Chk('timing: nested call, alive after the statement', destroyed, 0);
  f := nil;
  Chk('timing: nested call, function-result temp still holds it', destroyed, 0);
end;

{ The branch that never runs leaves its temp nil, and PXXIntfRelease is
  nil-safe -- so the object is still destroyed exactly once, by f := nil. }
procedure TimingBranchNotTaken;
var f: IFoo;
begin
  created := 0; destroyed := 0;
  f := TFoo.Create; Inc(created);
  if destroyed > 99 then TakeVal(f);
  f := nil;
  Chk('timing: untaken branch destroys exactly once', destroyed, 1);
end;

procedure Run(const what: string; n: Integer);
begin
  created := 0; destroyed := 0;
  case what[1] of
    'v': LoopVal(n);
    'c': LoopConst(n);
    'r': LoopVar(n);
    't': LoopTwo(n);
    'n': LoopNested(n);
    'o': OneCall;
  end;
  Chk(what + ' constructed', created, n);
  Chk(what + ' destructed', destroyed, n);
end;

begin
  pass := 0; fail := 0;

  Run('value param, 1 call', 1);
  Run('value param, 5 calls', 5);
  Run('value param, 50 calls', 50);
  Run('const param, 5 calls', 5);
  Run('rvar param, 5 calls', 5);
  Run('two params, same ref', 5);
  Run('nested calls, 5', 5);
  Run('one call, no loop', 1);

  TimingVal;
  TimingTwoSameRef;
  TimingNested;
  TimingBranchNotTaken;

  { and the same question from the MAIN BODY, where the temp used to live to
    program exit -- so nothing here could have destroyed it at all }
  created := 0; destroyed := 0;
  mf := TFoo.Create; Inc(created);
  TakeVal(mf);
  Chk('timing: main body, alive right after the call', destroyed, 0);
  mf := nil;
  Chk('timing: main body, dead at mf := nil', destroyed, 1);

  writeln;
  writeln('total ok ', pass, ' / ', pass + fail);
end.

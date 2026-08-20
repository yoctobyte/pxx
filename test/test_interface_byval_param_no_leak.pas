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

  NOTE ON TIMING: pxx releases the temp at the CALLER's scope exit, where FPC
  releases it at CALLEE return, so the last object of a batch dies later than
  under FPC. That is a separate, bounded divergence -- every object is still
  destroyed exactly once -- and it is why the counts below are checked AFTER the
  owning routine returns rather than inside it. See
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

  writeln;
  writeln('total ok ', pass, ' / ', pass + fail);
end.

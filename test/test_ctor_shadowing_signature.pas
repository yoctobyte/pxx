program TestCtorShadowingSignature;
{ bug-a-shadowing-ctor-call-target-and-argument-marshalling-disagree.

  A derived class declares `Create` with a DIFFERENT signature from the one it
  inherits. Two independent lookups then have to agree about which ctor a call
  means: the one that marshals the arguments (ir.inc, the -tkGetMem arg loop)
  and the one that becomes the call target (IRCtorProc). They did not — the
  first was FindUMeth, name-only and derived-first; the second was
  FindUCtorOverloadArgs, ranking the whole parent chain by argument type.

  So `TDer.Create('hello')` boxed the literal into a VARIANT (the derived
  signature) and called the BASE body, which read an AnsiString handle out of a
  Variant record and printed garbage. Silent wrong value, no diagnostic.

  What this test pins is NOT which ctor wins — that is a separate dialect
  question (FPC hides the inherited set when the descendant declares its own
  without `overload`, so FPC runs the DERIVED one here; pxx currently ranks by
  argument type and runs the base's exact AnsiString match). It pins the
  property that must hold whichever way that is decided: **the ctor that RUNS
  and the signature the ARGUMENT was marshalled for are the same one**, so the
  message arrives intact. Getting that wrong is garbage; getting the pick
  "wrong" is at worst a surprise that still prints the right string.

  Each line therefore asserts the MESSAGE, not the body that produced it. }

type
  TBase = class
    msg: AnsiString;
    constructor Create(const m: AnsiString);
    { A NAMED ctor shadowed the same way. `Create` has a parse fast path all to
      itself, so a named ctor reaches construction by a different route and
      needs its own assertion. }
    constructor Make(const m: AnsiString);
  end;
  TDer = class(TBase)
    constructor Create(const m: Variant);
    constructor Make(const m: Variant);
    procedure ViaInherited(const m: AnsiString);
  end;
  TDerClass = class of TDer;

var failures: Integer;

procedure Check(const got, want, what: AnsiString);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got [', got, '] want [', want, ']');
    failures := failures + 1;
  end;
end;

constructor TBase.Create(const m: AnsiString);
begin
  msg := m;
end;

constructor TBase.Make(const m: AnsiString);
begin
  msg := m;
end;

constructor TDer.Create(const m: Variant);
begin
  msg := m;
end;

constructor TDer.Make(const m: Variant);
begin
  msg := m;
end;

procedure TDer.ViaInherited(const m: AnsiString);
begin
  inherited Create(m);
end;

var
  d: TDer;
  b: TBase;
  o: TObject;
  cls: TDerClass;
  s: AnsiString;
  v: Variant;

begin
  failures := 0;

  { The literal is the case that produced garbage. }
  d := TDer.Create('hello');
  Check(d.msg, 'hello', 'shadowing ctor, string literal');

  { ...and an AnsiString VARIABLE, which produced a different, longer run of
    garbage — same defect, different length, because the two shapes reach the
    marshalling through different arg lowerings. }
  s := 'hello';
  d := TDer.Create(s);
  Check(d.msg, 'hello', 'shadowing ctor, string variable');

  { An argument that matches the DERIVED signature exactly always worked; it is
    here so a fix that simply stopped boxing everything would be caught. }
  v := 'hello';
  d := TDer.Create(v);
  Check(d.msg, 'hello', 'shadowing ctor, variant argument');

  { The base reached directly is the control — it was correct throughout, so a
    regression here means the fix moved the bug rather than removing it. }
  b := TBase.Create('hello');
  Check(b.msg, 'hello', 'base ctor named directly');

  { The SWEEP. A constructor is reachable by several routes and each resolves
    the ctor for itself, so each can carry the same disagreement independently.
    Measured against the pre-fix pinned compiler: only the plain `Create` above
    was ever broken and these five were already correct — they are here so they
    STAY correct, and because a future change to ctor resolution is exactly the
    kind that fixes one route and leaves the others behind. }
  d := TDer.Make('named');
  Check(d.msg, 'named', 'named shadowing ctor');

  cls := TDer;
  d := cls.Create('classof');
  Check(d.msg, 'classof', 'class-of dispatch, Create');
  d := cls.Make('classofnamed');
  Check(d.msg, 'classofnamed', 'class-of dispatch, named ctor');

  o := TDer.Create('seed');
  d := TDerClass(o.ClassType).Create('metacast');
  Check(d.msg, 'metacast', 'inline metaclass cast');

  d := TDer.Create('seed');
  d.ViaInherited('inherited');
  Check(d.msg, 'inherited', 'inherited Create from the derived body');

  if failures = 0 then WriteLn('ctor shadowing signature ok')
  else WriteLn('ctor shadowing signature FAILED ', failures);
end.

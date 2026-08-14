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
  end;
  TDer = class(TBase)
    constructor Create(const m: Variant);
  end;

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

constructor TDer.Create(const m: Variant);
begin
  msg := m;
end;

var
  d: TDer;
  b: TBase;
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

  if failures = 0 then WriteLn('ctor shadowing signature ok')
  else WriteLn('ctor shadowing signature FAILED ', failures);
end.

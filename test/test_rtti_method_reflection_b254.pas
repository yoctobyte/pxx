program test_rtti_method_reflection_b254;
{ Runtime discovery of PUBLISHED methods by name, and calling them — the mechanism
  a test framework finds its `Test*` methods with, and the one surface the self-host
  gate never exercises (feature-rtti-method-reflection).

  The RTTI blob already carried a {name, code} table for published methods; what was
  missing was a way for an INSTANCE to reach its own blob. The compiler now reserves
  a backlink word immediately BEFORE the VMT, so the blob is at [[instance+0] - 8].
  Slot indices and the is/as VMT-address identity are unchanged by that. }
uses rtti;

type
  TBaseCase = class
  published
    procedure TestInherited;
  end;

  TMyCase = class(TBaseCase)
  private
    FLog: string;
    procedure Helper;             { not published — must NOT be discovered }
  published
    procedure TestAlpha;
    procedure TestBeta;
  public
    property Log: string read FLog;
  end;

procedure TBaseCase.TestInherited;
begin
  writeln('ran TestInherited');
end;

procedure TMyCase.Helper;
begin
  writeln('ran Helper');          { never reached via reflection }
end;

procedure TMyCase.TestAlpha;
begin
  FLog := FLog + 'A';
end;

procedure TMyCase.TestBeta;
begin
  FLog := FLog + 'B';
end;

var
  c: TMyCase;
  i: Integer;
  m: TRttiProc;
begin
  c := TMyCase.Create;

  writeln('class=', GetRttiClassName(GetClassRtti(c)));
  writeln('count=', PublishedMethodCount(c));   { 2 own + 1 inherited }
  for i := 0 to PublishedMethodCount(c) - 1 do
    writeln('method=', PublishedMethodName(c, i));

  { private methods are invisible; lookup is case-insensitive like FPC }
  writeln('find-helper=', FindPublishedMethod(c, 'Helper') <> nil);
  writeln('find-missing=', FindPublishedMethod(c, 'Nope') <> nil);
  writeln('find-lowercase=', FindPublishedMethod(c, 'testbeta') <> nil);

  { the payoff: discover by name, bind, and RUN }
  m := BindPublishedMethod(c, 'TestAlpha');
  m();
  m := BindPublishedMethod(c, 'TestBeta');
  m();
  writeln('log=', c.Log);

  { an unpublished name binds to nothing rather than to garbage }
  m := BindPublishedMethod(c, 'Helper');
  writeln('helper-assigned=', Assigned(m));

  c.Free;
end.

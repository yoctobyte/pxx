program test_getinterface_guid_b257;
{$interfaces corba}  {non-refcounted CORBA interfaces on plain classes; FPC needs this too}
{ FPC's TObject.GetInterface(const IID: TGUID; out Obj): Boolean — look an implemented
  interface up BY GUID at runtime and hand back the interface value. Available with no
  `uses`, as FPC declares it on TObject in System.

  This needed a GUID to look up: the parser used to accept an interface's `['{...}']`
  literal and THROW IT AWAY, so there was nothing to search. The GUID is now recorded
  (16 raw bytes in TGuid memory order), and each class RTTI blob carries an interface
  table — one 24-byte entry per implemented interface that declared a GUID, holding the
  GUID inline plus a pointer to that (class, interface) IMT. The IMTs already existed;
  nothing had ever keyed them by GUID.

  A class that implements a guided interface now gets an RTTI blob even with NO
  published members, or a plain `class(TObject, IFoo)` would be invisible to the lookup.

  Both call shapes are covered, and the BARE one matters: it is exactly how fcl-fpcunit's
  testutils forwards an untyped `out` parameter —

      function TNoRefCountObject.QueryInterface(constref IID: TGUID; out Obj): HResult;
      begin
        if GetInterface(IID, Obj) then ...

  An AN_ADDR over a by-ref parameter auto-derefs to the CALLER's address, so the same
  rewrite serves a plain variable and a forwarded untyped `out` alike. }
type
  IFoo = interface
    ['{11111111-2222-3333-4444-555555555555}']
    function Hello: Integer;
  end;

  IBar = interface
    ['{99999999-8888-7777-6666-555555555555}']
    procedure Nope;
  end;

  { no published members on purpose: the blob must exist anyway }
  THolder = class(TObject, IFoo)
    function Hello: Integer;
    function QI(constref IID: TGuid; out Obj): Boolean;
  end;

function THolder.Hello: Integer;
begin
  Hello := 42;
end;

function THolder.QI(constref IID: TGuid; out Obj): Boolean;
begin
  QI := GetInterface(IID, Obj);        { BARE form — implicit Self }
end;

procedure MakeGuid(var g: TGuid; d1: Cardinal; d2, d3: Word;
                   b0, b1, b2, b3, b4, b5, b6, b7: Byte);
begin
  g.D1 := d1; g.D2 := d2; g.D3 := d3;
  g.D4[0] := b0; g.D4[1] := b1; g.D4[2] := b2; g.D4[3] := b3;
  g.D4[4] := b4; g.D4[5] := b5; g.D4[6] := b6; g.D4[7] := b7;
end;

var
  h: THolder;
  f: IFoo;
  b: IBar;
  gFoo, gBar: TGuid;
begin
  h := THolder.Create;
  MakeGuid(gFoo, $11111111, $2222, $3333, $44, $44, $55, $55, $55, $55, $55, $55);
  MakeGuid(gBar, $99999999, $8888, $7777, $66, $66, $55, $55, $55, $55, $55, $55);

  { qualified form, and the returned value must actually be CALLABLE }
  f := nil;
  writeln('qualified=', h.GetInterface(gFoo, f));
  writeln('call=', f.Hello);

  { an interface the class does not implement }
  writeln('miss=', h.GetInterface(gBar, b));

  { bare/implicit-Self form, forwarding an untyped `out` param }
  f := nil;
  writeln('bare=', h.QI(gFoo, f));
  writeln('call2=', f.Hello);

  h.Free;
end.

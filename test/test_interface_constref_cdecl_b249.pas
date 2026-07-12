program test_interface_constref_cdecl_b249;
{ Three gaps that fcl-fpcunit's testutils hits in one declaration:

    TNoRefCountObject = class(TObject, IInterface)
      function QueryInterface(constref IID: TGUID; out Obj): HResult; virtual; cdecl;

  1. `constref` (FPC: const, always by reference) was not recognised at all.
  2. An UNTYPED param in an INTERFACE method (`out Obj`) — the class-method and
     standalone paths allowed it, but the interface path demanded a ':'.
  3. A calling-convention directive (`cdecl`) in a class-body member's directive
     list; only ParseSubroutine accepted those.

  IInterface / IUnknown / HResult now come from the RTL's Classes (FPC declares
  them in System, which pxx has no auto-injected equivalent of). }
uses classes;

type
  TNoRef = class(TObject, IInterface)
  protected
    function QueryInterface(constref IID: TGuid; out Obj): HResult; virtual; cdecl;
    function _AddRef: Integer; cdecl;
    function _Release: Integer; cdecl;
  public
    procedure Ping; virtual; stdcall;
  end;

function TNoRef.QueryInterface(constref IID: TGuid; out Obj): HResult;
begin
  Result := -1;   { E_NOINTERFACE-ish: this object hands out no interfaces }
end;

function TNoRef._AddRef: Integer;
begin
  Result := -1;   { no refcounting }
end;

function TNoRef._Release: Integer;
begin
  Result := -1;
end;

procedure TNoRef.Ping;
begin
  writeln('ping');
end;

{ constref on a plain routine, and on a scalar }
procedure Show(constref n: Integer; constref s: string);
begin
  writeln('n=', n, ' s=', s);
end;

var
  o: TNoRef;
  g: TGuid;
begin
  o := TNoRef.Create;
  o.Ping;
  writeln('addref=', o._AddRef);
  writeln('release=', o._Release);
  g.D1 := 0;
  writeln('qi=', o.QueryInterface(g, o));
  o.Free;
  Show(7, 'hi');
end.

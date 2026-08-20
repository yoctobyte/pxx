program test_interface_containers;
{ COM interface elements inside CONTAINERS — the family that shared one absent
  descriptor kind (bug-a-a-local-array-of-interfaces-is-never-released-at-scope-exit,
  bug-a-a-local-dynamic-array-of-interfaces-is-not-released-at-scope-exit,
  bug-a-setlength-shrink-does-not-release-dropped-interface-elements).

  Every count below is FPC's answer, taken from an FPC differential run of this
  exact program, not from what pxx happened to print. Before the fix pxx printed
  0 for the first three and DANGLED on the fourth. }
type
  IFoo = interface
    ['{11111111-2222-3333-4444-555555555566}']
    function Name: string;
  end;
  TFoo = class(TInterfacedObject, IFoo)
  private
    FName: string;
  public
    constructor Create(const n: string);
    destructor Destroy; override;
    function Name: string;
  end;
var destroyed: Integer = 0;
    k: Integer;

constructor TFoo.Create(const n: string);
begin
  inherited Create;
  FName := n;
end;

destructor TFoo.Destroy;
begin
  Inc(destroyed);
  inherited Destroy;
end;

function TFoo.Name: string;
begin
  Result := FName;
end;

procedure StaticArr;
var i: Integer; keep: array[0..2] of IFoo;
begin
  for i := 0 to 2 do keep[i] := TFoo.Create('s');
end;

procedure LocalDyn;
var d: array of IFoo;
begin
  SetLength(d, 2);
  d[0] := TFoo.Create('a');
  d[1] := TFoo.Create('b');
end;

procedure Shrink;
var d: array of IFoo; i: Integer;
begin
  SetLength(d, 4);
  for i := 0 to 3 do d[i] := TFoo.Create('k');
  SetLength(d, 2);
  Writeln('after shrink: ', destroyed);
  SetLength(d, 0);
end;

procedure WholeCopy;
var a, b: array[0..1] of IFoo;
begin
  a[0] := TFoo.Create('p');
  a[1] := TFoo.Create('q');
  b := a;                       { must RETAIN both, not alias them }
  a[0] := nil; a[1] := nil;
  Writeln('after whole-copy nil-a: ', destroyed);
  Writeln('b still alive: ', b[0].Name, b[1].Name);
end;

{ A local `array of string` used to be claimed by the SCALAR AnsiString arm of
  the x86-64 epilogue (an array's TypeKind IS its element kind), which handed the
  array's DATA POINTER to the string releaser and freed nothing. The observable
  half of that here is that the elements still read back correctly after many
  calls; the leak itself is measured by RSS, not by a test. }
procedure StrArrRoundTrip;
var d: array of string; i: Integer;
begin
  SetLength(d, 4);
  for i := 0 to 3 do d[i] := 'e' + Chr(48 + i);
  if (d[0] <> 'e0') or (d[3] <> 'e3') then Writeln('strarr: WRONG');
end;

begin
  for k := 1 to 200 do StrArrRoundTrip;
  Writeln('strarr:  ok');
  destroyed := 0; StaticArr;  Writeln('static:  ', destroyed);
  destroyed := 0; LocalDyn;   Writeln('dyn:     ', destroyed);
  destroyed := 0; Shrink;     Writeln('shrink:  ', destroyed);
  destroyed := 0; WholeCopy;  Writeln('copy:    ', destroyed);
end.

program test_ro_rtti_write;
{ The positive control for read-only RTTI (the default; --no-ro-rtti turns it
  off): a class's VMT and its RTTI header live in the read-only segment, so a
  store into either must FAULT -- reached the way run-time code would, through
  an instance's VMT pointer and the RTTI backlink word at VMT-8. Under
  --no-ro-rtti both stores land.
  A flag whose RoRangeAdd silently no-oped would print a clean sweep; these rows
  are what make a clean sweep mean something.
  feature-a-there-is-no-read-only-load-segment-so-nothing-can-be-flash-resident }
{$mode objfpc}
type
  TBase = class
    Name: string;
    function Hello: string; virtual;
  published
    procedure Pub;
  end;
  TDer = class(TBase)
    function Hello: string; override;
  end;
function TBase.Hello: string; begin Result := 'base'; end;
procedure TBase.Pub; begin end;
function TDer.Hello: string; begin Result := 'der'; end;
var o: TBase; vmt: PPointer; blob: PPointer; mode: string;
begin
  mode := ParamStr(1);
  o := TDer.Create;
  o.Name := 'x' + 'y';
  WriteLn(o.Hello, ' ', o.ClassName, ' ', o is TBase, ' ', o is TDer);
  if mode = 'vmt' then
  begin
    vmt := PPointer(PPointer(o)^);
    WriteLn('before-vmt-write');
    vmt^ := vmt^;
    WriteLn('after-vmt-write');
  end
  else if mode = 'blob' then
  begin
    blob := PPointer((PByte(PPointer(o)^) - 8));
    blob := PPointer(blob^);
    WriteLn('before-blob-write');
    blob^ := blob^;
    WriteLn('after-blob-write');
  end;
  o.Free;
  WriteLn('done');
end.

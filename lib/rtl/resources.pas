unit resources;

{ Runtime access to embedded resources (see the R directive). The compiler
  emits a table (count, then name/data/len triples) reachable via the
  __resources intrinsic; FindResource linearly walks it, like typinfo.GetClass. }

interface

uses typinfo;   { PString — declaring it here too would duplicate the type and corrupt RTTI }

type
  { Emitted (resources_emit.inc) as uniform 8-byte slots: nameptr(8), dataptr(8),
    len(8) = 24 bytes/entry. Pad the pointer fields on 32-bit so the reader stride
    matches the blob (else `e[i]` steps 16 bytes and reads garbage). Mirrors the
    typinfo RTTI-record padding. }
  TResEntry = record
    NamePtr: PString;
    {$ifdef CPU32} _pad_name: LongInt; {$endif}
    DataPtr: Pointer;
    {$ifdef CPU32} _pad_data: LongInt; {$endif}
    Len:     Int64;
  end;
  PResEntry = ^TResEntry;

  TResTable = record
    Count: Int64;
    Dummy: TResEntry;
  end;
  PResTable = ^TResTable;

function FindResource(const name: string; var data: Pointer; var len: Integer): Boolean;

implementation

function FindResource(const name: string; var data: Pointer; var len: Integer): Boolean;
var
  t: PResTable;
  e: PResEntry;
  i: Integer;
begin
  Result := False;
  data := nil;
  len := 0;
  t := __resources();
  if t = nil then Exit;
  e := @t^.Dummy;
  for i := 0 to Integer(t^.Count) - 1 do
  begin
    if e[i].NamePtr^ = name then
    begin
      data := e[i].DataPtr;
      len := Integer(e[i].Len);
      Result := True;
      Exit;
    end;
  end;
end;

end.

program test_rtti_reg;

type
  TBase = class
  published
    procedure Notify;
  end;

  TChild = class(TBase)
  published
    procedure Callback;
  end;

procedure TBase.Notify; begin end;
procedure TChild.Callback; begin end;

type
  { RTTI names are frozen, word-length-prefixed blobs; under the managed-string
    default a name pointer must be a frozen-string pointer (string[255]) to read
    the inline [len][chars] correctly — `^string` would treat the length word as
    a managed handle and crash. }
  TRttiStr = string[255];
  PString = ^TRttiStr;
  TRTTIEntry = record
    NamePtr: PString;
    RTTIPtr: Pointer;
  end;
  PRTTIEntry = ^TRTTIEntry;

  TRegistry = record
    Count: Int64;
    Dummy: TRTTIEntry;
  end;
  PRegistry = ^TRegistry;

var
  reg: PRegistry;
  entries: PRTTIEntry;
  i: Integer;
begin
  reg := __rttireg();
  if reg = nil then
  begin
    writeln('no RTTI registry found');
    Halt(1);
  end;

  writeln('Count: ', reg^.Count);
  
  { entries start immediately after Count }
  entries := @reg^.Dummy;

  for i := 0 to Integer(reg^.Count) - 1 do
  begin
    writeln('Class ', i, ': ', entries[i].NamePtr^);
  end;
end.

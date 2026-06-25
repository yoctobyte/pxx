program test_method_read_write_unqualified;

{ An unqualified Read/Write call STATEMENT inside a method whose class has a
  Read/Write member must bind to the member (Self.Read/Self.Write), not the
  console/file intrinsic. This was the TStream.CopyFrom symptom: `Write(buf,n)`
  printed to stdout instead of calling Self.Write. See
  bug-bare-read-write-in-method-hits-intrinsic. }

type
  TBuf = class
    data: Integer;
    procedure Write(v: Integer);          { shadows the console Write intrinsic }
    procedure Read(var dst: Integer); virtual;  { virtual -> exercise the VMT path }
    procedure Run;
  end;

procedure TBuf.Write(v: Integer);
begin
  data := v * 2;
end;

procedure TBuf.Read(var dst: Integer);
begin
  dst := data + 1;
end;

procedure TBuf.Run;
var r: Integer;
begin
  Write(21);                 { Self.Write -> data := 42 (NOT a console print) }
  Read(r);                   { Self.Read  -> r := 43    (NOT a stdin read)    }
  writeln('data=', data);    { 42 }
  writeln('r=', r);          { 43 }
end;

var
  b: TBuf;
begin
  b := TBuf.Create;
  b.Run;
  b.Free;
end.

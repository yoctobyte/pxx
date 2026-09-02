program test_method_read_write_unqualified;

{ An unqualified Read/Write call STATEMENT inside a method whose class has a
  Read/Write member must bind to the member (Self.Read/Self.Write), not the
  console/file intrinsic. This was the TStream.CopyFrom symptom: `Write(buf,n)`
  printed to stdout instead of calling Self.Write. See
  bug-bare-read-write-in-method-hits-intrinsic.

  AND THE OTHER DIRECTION, which is the half that was missing: a call NO
  overload of the member can accept must fall through to the intrinsic instead
  of binding to the member anyway. A test that only asserts the binding cannot
  fail when the binding becomes unconditional -- which it was, on the name
  alone, until FindUMethArityStrict. `Write(f, ...)` with a Text file inside a
  method named `write` bound to the 1-parameter member and emitted a
  3-argument call: i386/arm32/aarch64 refuse it, x86-64 emitted it, and the
  file came out EMPTY while the function returned True. That is the shape
  lib/rtl/configparser.pas is written in, and FPC rejects the same source
  outright, so it built nowhere and ran wrong where it built.
  bug-p-a-write-call-inside-a-method-named-write-binds-to-the-member-whatever-its-arity }

type
  TBuf = class
    data: Integer;
    procedure Write(v: Integer);          { shadows the console Write intrinsic }
    procedure Read(var dst: Integer); virtual;  { virtual -> exercise the VMT path }
    procedure Run;
    function spill(const path: AnsiString): Boolean;
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

{ The must-fall-through case. Every call below is spelled `Write`, inside a
  class that HAS a Write member, and only the two-argument file form may reach
  the intrinsic -- the member takes one Integer. }
function TBuf.spill(const path: AnsiString): Boolean;
var f: Text; n: Integer;
begin
  spill := False;
  Assign(f, path);
  {$I-}
  Rewrite(f);
  {$I+}
  if IOResult <> 0 then Exit;
  Write(f, 'payload');       { the INTRINSIC: no Write member takes (Text, str) }
  Close(f);
  { Read it back rather than trusting the return value -- the defect this
    guards reported success and wrote nothing, so a check of the result alone
    passes on the broken compiler. }
  Assign(f, path);
  {$I-}
  Reset(f);
  {$I+}
  if IOResult <> 0 then Exit;
  n := 0;
  while not Eof(f) do begin ReadLn(f); Inc(n); end;
  Close(f);
  spill := n = 1;
end;

var
  b: TBuf;
  tmp: AnsiString;
begin
  b := TBuf.Create;
  b.Run;
  tmp := '/tmp/pxx_test_method_rw_unqualified.txt';
  if b.spill(tmp) then writeln('spill=OK') else writeln('spill=FAIL');
  b.Free;
end.

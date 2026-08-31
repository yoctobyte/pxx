program test_setlen_through_pointer_and_capture;
{ SetLength on a MANAGED STRING reached through a pointer deref.

  ThroughPointer is the REGRESSION CONTROL: a hand-written `p: ^AnsiString`
  with `SetLength(p^, n)`. FPC accepts it; `pinned` (992065f21f33) refuses this
  file at that line, so the test is known to be able to fail. The classifier saw
  the POINTER symbol -- tyPointer, not tyAnsiString -- and routed the target to
  the FROZEN-string path, which surfaced two phases later as `SetLength expects
  a string variable in IR codegen` against a line in lib/rtl/strings.pas. The
  diagnostic named neither the program nor the limitation, which is most of why
  it survived.

  ThroughCapture is NOT a control and must not be read as one. A plain nested
  routine capturing an AnsiString ALREADY WORKED -- verified on `pinned`, which
  compiles that shape alone and prints the same line. It is here to pin the
  BOUNDARY, because the obvious summary of this bug ("SetLength on a captured
  string is refused") is false in exactly this case and true one lowering over:
  a `parallel for` body passes the captured string by pointer and WAS refused.
  That shape needs --threadsafe and lives in
  test_setlen_in_parallel_for_body.pas.

  Values checked against FPC 3.2.2, which prints these three lines exactly. }
{$mode objfpc}{$H+}
type PStr = ^AnsiString;

procedure ThroughPointer;
var s: AnsiString; p: PStr; i: LongInt;
begin
  s := 'abc';
  p := @s;
  SetLength(p^, 6);                 { grow through the deref }
  for i := 4 to 6 do p^[i] := 'z';
  WriteLn('ptr grow  len=', Length(s), ' s=', s);
  SetLength(p^, 2);                 { and shrink }
  WriteLn('ptr shrink len=', Length(s), ' s=', s);
end;

procedure ThroughCapture;
var s: AnsiString;

  procedure Inner;                  { lifted: s arrives by pointer }
  var i: LongInt;
  begin
    SetLength(s, 5);
    for i := 1 to 5 do s[i] := 'q';
  end;

begin
  s := '';
  Inner;
  WriteLn('cap       len=', Length(s), ' s=', s);
end;

begin
  ThroughPointer;
  ThroughCapture;
end.

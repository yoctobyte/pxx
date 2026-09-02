{ A MANAGED ARGUMENT TEMP IN A FRAME AN EXCEPTION UNWINDS PAST MUST BE RELEASED.

  The temp is hidden: `Exception.Create(gmsg + Chr(65))` builds an AnsiString
  nobody named, hands it to the constructor, and the frame is then unwound past
  before its scope exit runs. One heap block per raise, unbounded -- a program
  that raises in a loop grows without limit. FPC 3.2.2 with -gh reports
  `0 unfreed memory blocks` on these same shapes, so this is a divergence on
  code someone meant to write.

  WHY IT WAS INVISIBLE: the landing pad that releases such a frame's managed
  values was gated on ProcHasManagedLocalCleanup, asked in the PROLOGUE. The
  hidden temps are minted by IRLowerAST while lowering the BODY, long after. The
  gate was not filtering them out -- it was asked before they existed, so it was
  structurally incapable of a different answer. It is now asked a second time
  inside CompileAST, between lowering and emission, where both conditions hold.

  ROW 3 IS THE ONE A CHEAP FIX FAILS. The temp belongs to Caller and the raise
  happens in Callee, so anything that only drains temps at a `raise` statement
  leaves it. Row 4 is the same at depth 4.

  NOTHING HERE MAY DECLARE A MANAGED LOCAL IN A RAISING ROUTINE. Merely
  declaring an unused AnsiString switches the landing pad on by the OLD gate and
  takes the temps with it -- so a well-meaning `s: AnsiString` added to any
  routine below silently converts this file into a test that passes on the
  broken compiler. An Integer local does not have that effect; that asymmetry is
  the bug's signature, not a coincidence.

  Row 1 is the discriminator that says this is about the UNWIND path and not
  about temps: the same temp, in the same shape, on the NORMAL path, was always
  released correctly.
  bug-a-a-managed-temp-in-a-frame-unwound-by-an-exception-is-never-released }
program test_exception_unwind_temp_leak;

uses SysUtils;

const N = 3000;

var
  gmsg: AnsiString;
  i, normalPath: Integer;

{ row 1: a managed temp, NO raise -- the normal path, always correct }
procedure NoRaise;
begin
  if Length(gmsg + Chr(65)) > 0 then normalPath := 1;
end;

{ row 2: the temp is an argument of the raise itself }
procedure RaiseWithTemp;
begin
  raise Exception.Create(gmsg + Chr(65));
end;

{ row 3: the temp belongs to Caller; Callee raises }
procedure Callee(const s: AnsiString);
begin
  raise Exception.Create(gmsg);
end;

procedure Caller;
begin
  Callee(gmsg + Chr(65));
end;

{ row 4: same, four frames deep }
procedure L4;
begin
  raise Exception.Create(gmsg);
end;

procedure L3(const s: AnsiString);
begin
  L4;
end;

procedure L2;
begin
  L3(gmsg + Chr(66));
end;

procedure L1;
begin
  L2;
end;

begin
  gmsg := 'x';
  normalPath := 0;

  for i := 1 to N do NoRaise;
  if normalPath <> 1 then
  begin WriteLn('FAIL: row 1 never ran'); Halt(1); end;

  for i := 1 to N do
    try RaiseWithTemp except on E: Exception do ; end;

  for i := 1 to N do
    try Caller except on E: Exception do ; end;

  for i := 1 to N do
    try L1 except on E: Exception do ; end;

  WriteLn('UNWIND TEMP OK');
end.

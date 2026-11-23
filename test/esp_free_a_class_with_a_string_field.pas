program esp_free_a_class_with_a_string_field;
{ Freeing a class with a managed field recursed until the stack ran out on
  ESP: the DCE cut of PXXClassFinalize's call to PXXClassMgmtRun (a BACKWARD
  call, its target recorded when it was emitted) kept the old target, which
  after compaction was PXXClassFinalize itself. Found as json.loads crashing
  on ESP32-C3 hardware (rfid project); this is the minimal form.
  bug-a-a-dce-cut-backward-call-keeps-its-old-target-and-recurses-on-esp }
type
  TR = class
    FSrc: AnsiString;
    FPos: Integer;
  end;
var r: TR; s: AnsiString;
begin
  WriteLn('PXX-free start');
  r := TR.Create;
  s := 'abc';
  s := s + 'def';
  r.FSrc := s;
  WriteLn('PXX-free created ', r.FSrc);
  r.Free;
  WriteLn('PXX-free freed');
end.

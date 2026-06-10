program test_syncobjs;

uses syncobjs;

var
  cs: TCriticalSection;
begin
  cs := TCriticalSection.Create;
  cs.Enter;
  writeln(1);
  cs.Leave;
  cs.Acquire;
  if cs.TryEnter then writeln(2);
  cs.Release;
  writeln(3);
end.

{ POSITIVE half, and the row that says the narrowing above went the right way:
  a NAMED, top-level record's `class var` is accepted and behaves like one --
  ONE storage slot shared by the type, not a field per instance. Written as a
  behaviour assertion rather than a compiles/does-not-compile check, because
  "it parses" would pass even if the slot were per-instance. }
program test_record_class_var_ok;
type
  TCounter = record
  class var
    Count: Integer;
    procedure Bump;
  end;
procedure TCounter.Bump;
begin
  TCounter.Count := TCounter.Count + 1;
end;
var
  a, b: TCounter;
begin
  TCounter.Count := 0;
  a.Bump;
  b.Bump;
  a.Bump;
  { three bumps through two different instances land in ONE slot }
  writeln('count = ', TCounter.Count);
  writeln('via a = ', a.Count);
  writeln('via b = ', b.Count);
  writeln('RECORD CLASS VAR OK');
end.

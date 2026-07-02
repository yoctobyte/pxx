program test_threadsafe_io_lock;
{ --threadsafe statement-atomic I/O lock, single-threaded semantics pin
  (feature-threadsafe-io-serialization): the reentrant owner-tid lock must
  not deadlock when a write argument calls a function that itself writes,
  and output equals the unlocked ordering (write args emit left-to-right as
  they evaluate, so 'outer ' precedes the inner line — FPC does the same). The threaded-interleave acceptance
  is blocked on bug-tthread-execute-crash (threads crash in Execute today
  regardless of I/O). Compile this WITH --threadsafe (Makefile does). }
function Noisy(x: Integer): Integer;
begin
  writeln('inner ', x);
  Noisy := x * 2;
end;
var i: Integer; s: AnsiString;
begin
  writeln('outer ', Noisy(21));
  for i := 1 to 3 do
  begin
    s := 'line' + Chr(48 + i);
    writeln(s, ' ', i * 10);
  end;
  writeln('done');
end.

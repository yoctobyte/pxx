program threadsafe_io_writeln;
{ The --threadsafe I/O lock's per-statement cost, held against the same program
  built without the lock. Run both to /dev/null and take the MIN of an
  interleaved A/B; the interesting number is the RATIO, not either time.

  Shape chosen because it is the worst case for the lock: 400k of the shortest
  possible Writeln, so the lock's fixed cost per statement is not hidden behind
  any real work. Each Writeln is two write(2) calls (payload, newline), which is
  the bigger constant next door and is NOT what this measures.

  Numbers and the compiler shas they came from:
  benchmarks/2026-08-31-threadsafe-io-lock-tls.md. }
var i: Integer;
begin
  for i := 1 to 400000 do
    Writeln('x');
end.

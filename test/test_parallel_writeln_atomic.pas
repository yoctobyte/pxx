program test_parallel_writeln_atomic;
{ --threadsafe statement-atomic console I/O from `parallel for` WORKERS (not
  TThread). Every worker writes ONE pre-built 100-char line (A*49 '-' idx:4
  '-' B*49); the lines are built in the main thread and only READ in the
  parallel body, so this isolates the I/O lock (IR_IO_LOCK) from the managed
  heap. Without the lock the 100-char lines tear mid-write. Cross-target gate
  for feature-threadsafe-io-lock-cross: the lock is emitted + lowered on
  x86-64/i386/aarch64/arm32, so every line stays atomic on all four.
  The Makefile greps: exactly 200 well-formed lines, then 'PARWROK'.
  NOTE: workers deliberately do NOT allocate — concurrent per-worker managed
  string alloc is a separate open heap bug (bug-a-threadsafe-heap-parallel-for-
  managed-string-race). }
uses palparallel;

const N = 200;
type TLines = array[0..N-1] of AnsiString;
var lines: TLines;

function D4(n: Integer): AnsiString;
begin
  D4 := Chr(48 + (n div 1000) mod 10) + Chr(48 + (n div 100) mod 10) +
        Chr(48 + (n div 10) mod 10) + Chr(48 + n mod 10);
end;

procedure Run;
var i: Integer;
begin
  parallel for i := 0 to N-1 do
    writeln(lines[i]);          { read-only: no worker heap alloc }
end;

var i: Integer; a, b: AnsiString;
begin
  a := ''; b := '';
  for i := 1 to 49 do begin a := a + 'A'; b := b + 'B'; end;
  for i := 0 to N-1 do lines[i] := a + '-' + D4(1000 + i) + '-' + b;
  Run;
  writeln('PARWROK');
end.

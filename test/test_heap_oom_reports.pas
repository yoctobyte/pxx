program test_heap_oom_reports;
{ An arena mmap that FAILS must be reported, not faulted through.

  PXXAlloc used to ignore HeapMmap's return -- a stated decision, reversed for
  hosted targets in bug-a-pxxalloc-does-not-check-the-mmap-return-so-oom-
  arrives-as-an-anonymous-segv. The -ENOMEM became the heap base and the size
  header write faulted on it, so an out-of-memory condition arrived as an
  anonymous SIGSEGV with no diagnostic. It cost two sessions.

  Measured contrast, same binary, same 200 MB cap:
    pinned 992065f21f33   Segmentation fault, exit 139, no output
    fixed  f23f141f997d   "pxx: out of memory (heap arena mmap failed)", exit 203

  So this test has its positive control in its own history: it is a case the
  pre-fix compiler DEMONSTRABLY fails, not one asserted to be covered.

  The Makefile runs this under `ulimit -v` below HEAP_ARENA (256 MB), so the
  FIRST arena request is refused and the failure is deterministic rather than
  dependent on how much the box happens to have free. Doubling from one byte
  reaches that in 30 steps and would want a gigabyte unconstrained, so the
  program is a real allocator workload either way.

  203 is FPC's heap-overflow runtime error; the Makefile asserts the exit code
  AND the message, because either alone would pass for the wrong reason -- a
  segfault that happened to be reported as 203 by a shell, or a message printed
  on a path that then carried on. }
var s: AnsiString; i: Integer;
begin
  s := 'x';
  for i := 1 to 30 do s := s + s;
  { Not reached under the cap. Printed rather than silent so that a run which
    DOES reach it fails the expected-output check loudly instead of looking
    like a pass. }
  WriteLn('UNEXPECTED: allocated len=', Length(s));
end.

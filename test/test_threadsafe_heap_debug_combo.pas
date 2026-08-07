program test_threadsafe_heap_debug_combo;
{ bug-a-threadsafe-plus-heap-debug-hangs-at-runtime

  Built with BOTH --threadsafe and -dPXX_HEAP_DEBUG this HUNG at run time, while
  either flag alone was fine. That is the combination a hard bug actually wants:
  a refcount problem that only shows under threading is exactly what the debug
  heap's poison and quarantine exist to diagnose.

  Single-threaded self-deadlock on the heap spinlock. On x86-64 --threadsafe the
  lock is hand-emitted, and EmitHeapFreeLocked calls PXXFree from INSIDE the
  locked region. PXXFree ends by calling PXXDbgFlush, which held a managed local
  `msg: string`; finalizing that local on the way out re-entered the emitted
  string-release blob, which takes the same lock. `lock xchg` then spun forever
  — one thread, one lock, taken twice.

  The Makefile builds this file three ways: --threadsafe alone, -dPXX_HEAP_DEBUG
  alone, and both together. All three must print the same thing and exit. The
  combined build is the regression guard; the two single-flag builds are there
  so a fix cannot "pass" by disabling either mode.

  Everything here is deliberately managed-string work, because that is what
  reaches the locked free path — an integer-only program never did hang. }

var
  s, t: AnsiString;
  i: Integer;

begin
  s := 'threadsafe';
  for i := 1 to 100 do
    s := s + '.';
  { share, so the release below is a refcount drop and not a free }
  t := s;
  WriteLn(Length(s), ' ', Length(t));

  { drop one reference: the survivor must be intact and readable }
  s := '';
  WriteLn(Length(t), ' survivor-ok');

  { churn: many short-lived strings, each one a locked alloc + locked free,
    which is the path that deadlocked }
  s := '';
  for i := 1 to 200 do
  begin
    t := 'block';
    t := t + 'x';
    s := t;
  end;
  WriteLn(s, ' churn-ok');
end.

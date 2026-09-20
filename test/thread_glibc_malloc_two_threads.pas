program thread_glibc_malloc_two_threads;

{ WIRED into `test-threads` since 2026-09-20, and it now must PASS.

  It was the positive control for
  bug-a-a-pxx-created-thread-shares-glibc-s-thread-pointer-so-two-threads-share-one-malloc-state
  and was EXPECTED TO ABORT -- 5/5 with `free(): too many chunks detected in
  tcache` -- so it was held out to keep a permanent RED out of every session's
  gate. That bug was fixed by `934ba0418` on 2026-09-14 (pxx threads route
  through pthread_create when libc is already linked) and this file's previous
  header said to wire it in that commit. IT WAS NOT, AND NOBODY NOTICED FOR SIX
  DAYS, because the instruction lived in a source header and nothing scans one.
  Re-measured on 2026-09-20 before wiring rather than assumed: 5/5 survive.
  It needs `--threadsafe`, which __pxxclone has required since the fix. }
{ Two threads, both churning GLIBC's malloc. pxx's own heap is mmap-backed and
  is deliberately NOT the subject: every allocation below is libc's.

  PXX_CLONE_THREAD (lib/rtl/palthread.pas:92) omits CLONE_SETTLS, so a pxx
  thread inherits the parent's `fs` base. devdocs/dev/threading.md says so and
  explains why pxx's OWN thread pointer moved to `gs` -- taking `fs` destroyed
  libc's TLS for the main thread. What that reasoning does not say is that
  leaving `fs` INHERITED makes glibc's thread-locals SHARED between the main
  thread and every thread pxx creates. glibc keeps `tcache` and `thread_arena`
  there and takes no lock on them, because they are per-thread by construction.

  If that is the mechanism, this program corrupts glibc's heap. If it survives,
  the mechanism is something else and this negative is worth as much. }
uses palthread;

const
  ROUNDS = 400000;

function c_malloc(n: NativeUInt): Pointer; cdecl; external 'libc.so.6' name 'malloc';
procedure c_free(p: Pointer); cdecl; external 'libc.so.6' name 'free';

var
  h: TThreadHandle;
  mainSeen, workerSeen: Int64;

procedure Churn(var seen: Int64);
var
  i: Integer;
  p: Pointer;
begin
  for i := 1 to ROUNDS do
  begin
    { Sizes stay inside glibc's tcache range (<= 1032 bytes), which is the
      structure with no lock on it. A size sweep keeps several bins busy. }
    p := c_malloc(24 + (i mod 96) * 8);
    if p <> nil then c_free(p);
    seen := seen + 1;
  end;
end;

procedure WorkerEntry(arg: Pointer); cdecl;
begin
  Churn(workerSeen);
  PalThreadExit;
end;

begin
  mainSeen := 0;
  workerSeen := 0;
  if PalThreadCreate(h, @WorkerEntry, nil, 0) <> 0 then
  begin
    WriteLn('INSTRUMENT DEAD: could not create the thread, this run proves nothing');
    Halt(2);
  end;
  Churn(mainSeen);
  PalThreadJoin(h);
  WriteLn('main churned ', mainSeen, ' worker churned ', workerSeen);
  if (mainSeen = 0) or (workerSeen = 0) then
    WriteLn('INSTRUMENT DEAD: one side never ran, this run proves nothing')
  else
    WriteLn('survived: both threads churned glibc malloc concurrently');
end.

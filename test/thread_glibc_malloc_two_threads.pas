program thread_glibc_malloc_two_threads;

{ NOT WIRED INTO THE MAKEFILE, deliberately, and this is the note that says so.

  This program is EXPECTED TO ABORT on today's compiler -- it is the positive
  control for
  bug-a-a-pxx-created-thread-shares-glibc-s-thread-pointer-so-two-threads-share-one-malloc-state,
  drawn from exactly the population that bug is about. Wiring it in now would
  put a permanent RED into every session's gate for a known open bug, which is
  the bookkeeping-stall failure mode CLAUDE.md names. Wire it, and its controls
  beside it, in the commit that fixes the PAL -- the controls are what localise
  a future regression to the thread pointer rather than to the churn. }
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

program thread_glibc_malloc_controls;

{ NOT WIRED INTO THE MAKEFILE, deliberately, and this is the note that says so.

  These are the two CONTROLS (both pass today) for
  bug-a-a-pxx-created-thread-shares-glibc-s-thread-pointer-so-two-threads-share-one-malloc-state,
  drawn from exactly the population that bug is about. They are held out with the repro they
  belong to, because a control that ships without its positive control is a
  guard that cannot fail. Wire all three in the commit that fixes the PAL -- the controls are what localise
  a future regression to the thread pointer rather than to the churn. }
{ The two controls for test/thread_glibc_malloc_two_threads.pas, which aborts 5/5 with
  `free(): too many chunks detected in tcache`.

  CONTROL A -- the same churn, twice as many rounds, ONE thread. If this
  aborted, the churn itself would be the defect and the thread would be
  incidental. It must survive.

  CONTROL B -- the same churn on two threads again, but the second thread is
  created by GLIBC'S OWN pthread_create instead of PalThreadCreate. A
  pthread_create thread gets CLONE_SETTLS and its own `fs` block, so it gets
  its own tcache. If the mechanism is the shared thread pointer, this must
  survive while tcache.pas aborts -- same work, same libc, same machine, one
  difference.

  Run with an argument: `ctl a` or `ctl b`. }

const
  ROUNDS = 400000;

function c_malloc(n: NativeUInt): Pointer; cdecl; external 'libc.so.6' name 'malloc';
procedure c_free(p: Pointer); cdecl; external 'libc.so.6' name 'free';
function c_pthread_create(var tid: NativeUInt; attr: Pointer;
                          entry: Pointer; arg: Pointer): Integer;
                          cdecl; external 'libc.so.6' name 'pthread_create';
function c_pthread_join(tid: NativeUInt; ret: Pointer): Integer;
                        cdecl; external 'libc.so.6' name 'pthread_join';

var
  mainSeen, workerSeen: Int64;
  tid: NativeUInt;

procedure Churn(var seen: Int64; rounds: Integer);
var
  i: Integer;
  p: Pointer;
begin
  for i := 1 to rounds do
  begin
    p := c_malloc(24 + (i mod 96) * 8);
    if p <> nil then c_free(p);
    seen := seen + 1;
  end;
end;

function PosixEntry(arg: Pointer): Pointer; cdecl;
begin
  Churn(workerSeen, ROUNDS);
  PosixEntry := nil;
end;

var
  mode: AnsiString;
begin
  mainSeen := 0;
  workerSeen := 0;
  if ParamCount >= 1 then mode := ParamStr(1) else mode := 'a';

  if mode = 'a' then
  begin
    Churn(mainSeen, ROUNDS * 2);
    WriteLn('CONTROL A single thread: churned ', mainSeen);
    if mainSeen = 0 then
      WriteLn('INSTRUMENT DEAD: nothing ran, this run proves nothing')
    else
      WriteLn('CONTROL A survived');
  end
  else
  begin
    if c_pthread_create(tid, nil, @PosixEntry, nil) <> 0 then
    begin
      WriteLn('INSTRUMENT DEAD: pthread_create failed, this run proves nothing');
      Halt(2);
    end;
    Churn(mainSeen, ROUNDS);
    if c_pthread_join(tid, nil) <> 0 then
    begin
      WriteLn('INSTRUMENT DEAD: pthread_join failed, this run proves nothing');
      Halt(2);
    end;
    WriteLn('CONTROL B glibc thread: main ', mainSeen, ' worker ', workerSeen);
    if (mainSeen = 0) or (workerSeen = 0) then
      WriteLn('INSTRUMENT DEAD: one side never ran, this run proves nothing')
    else
      WriteLn('CONTROL B survived');
  end;
end.

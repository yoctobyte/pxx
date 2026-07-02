program test_tthread_sync;
{ M3 TThread parity: Synchronize (blocking main-thread marshalling), Queue
  (fire-and-forget), CheckSynchronize (main-thread pump), and the auto-join
  virtual destructor (t.Free alone Terminates + WaitFors a running thread).
  syncCounter/queueCounter are deliberately UNGUARDED — correct only if every
  increment really runs on the main thread. Compile with --threadsafe. }
uses palthread, palthreadobj;

const
  NT = 4;
  NCALLS = 50;

var
  syncCounter:  Integer;   { touched only via Synchronize -> main thread }
  queueCounter: Integer;   { touched only via Queue -> main thread }
  syncOnMain:   Integer;   { how many Synchronize bodies saw the main tid }

type
  TWorker = class(TThread)
  public
    procedure AddSync;
    procedure AddQueue;
  protected
    procedure Execute; override;
  end;

  TStopper = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TWorker.AddSync;
begin
  syncCounter := syncCounter + 1;
  if PalThreadSelf = MainThreadID then syncOnMain := syncOnMain + 1;
end;

procedure TWorker.AddQueue;
begin
  queueCounter := queueCounter + 1;
end;

procedure TWorker.Execute;
var
  i: Integer;
  ms, mq: TThreadMethod;
begin
  { @Self.Method is an assignment-side construct today; a direct
    Synchronize(@Self.AddSync) argument is not parsed yet. }
  ms := @Self.AddSync;
  mq := @Self.AddQueue;
  for i := 1 to NCALLS do Self.Synchronize(ms);
  for i := 1 to NCALLS do Self.Queue(mq);
end;

procedure TStopper.Execute;
begin
  { spin until the destructor's Terminate reaches us (cooperative cancel) }
  while not Self.Terminated do ;
end;

var
  w: array[0..NT-1] of TWorker;
  wk: TWorker;
  t: TStopper;
  i, nFin: Integer;
  drained: Boolean;
begin
  syncCounter := 0; queueCounter := 0; syncOnMain := 0;

  for i := 0 to NT - 1 do w[i] := TWorker.Create(True);
  for i := 0 to NT - 1 do w[i].Start;

  { pump the sync queue until every worker's Execute has returned }
  repeat
    drained := CheckSynchronize;
    nFin := 0;
    for i := 0 to NT - 1 do
      if w[i].Finished then nFin := nFin + 1;
  until (nFin = NT) and (not drained);
  for i := 0 to NT - 1 do w[i].WaitFor;
  drained := CheckSynchronize;   { catch stragglers queued just before exit }

  writeln('sync=', syncCounter, ' expected=', NT * NCALLS);
  writeln('onmain=', syncOnMain, ' expected=', NT * NCALLS);
  writeln('queue=', queueCounter, ' expected=', NT * NCALLS);

  { auto-join destructor: Free alone must Terminate + join a running thread }
  t := TStopper.Create(False);
  t.Free;
  writeln('autojoin OK');

  for i := 0 to NT - 1 do
  begin
    { indexed `w[i].Free` is not parsed yet — Free wants a plain variable }
    wk := w[i];
    wk.Free;
  end;
  if (syncCounter = NT * NCALLS) and (syncOnMain = NT * NCALLS) and
     (queueCounter = NT * NCALLS) then
    writeln('TTHREAD SYNC OK')
  else
    writeln('TTHREAD SYNC FAIL');
end.

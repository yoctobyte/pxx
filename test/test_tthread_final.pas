program test_tthread_final;
{ M3 TThread final slice: FreeOnTerminate (self-free + handle reaper),
  OnTerminate (marshalled to the main thread), CurrentThread (registry +
  main placeholder), Suspend/Resume (cooperative self-park), and the legacy
  Create(True) + Resume = Start pattern. Compile with --threadsafe. }
uses palthread, palthreadobj;

var
  curOk:        Integer;   { workers whose CurrentThread = Self }
  termOnMain:   Integer;   { OnTerminate bodies that ran on the main tid }
  fotDone:      Integer;   { set by the FreeOnTerminate worker before exit }
  suspWork:     Integer;   { phase marker around Suspend/Resume }
  lateStartRan: Integer;   { Create(True) + Resume path }

type
  TCurWorker = class(TThread)
  public
    procedure Terminated_;
  protected
    procedure Execute; override;
  end;

  TFotWorker = class(TThread)
  protected
    procedure Execute; override;
  end;

  TSuspWorker = class(TThread)
  protected
    procedure Execute; override;
  end;

  TLateWorker = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TCurWorker.Terminated_;
begin
  if PalThreadSelf = MainThreadID then termOnMain := termOnMain + 1;
end;

procedure TCurWorker.Execute;
begin
  if CurrentThread = Self then curOk := curOk + 1;
end;

procedure TFotWorker.Execute;
begin
  fotDone := 1;
end;

procedure TSuspWorker.Execute;
begin
  suspWork := 1;
  Self.Suspend;          { park until the main thread Resumes us }
  suspWork := 2;
end;

procedure TLateWorker.Execute;
begin
  lateStartRan := 1;
end;

var
  c:  TCurWorker;
  f:  TFotWorker;
  s:  TSuspWorker;
  l:  TLateWorker;
  mt: TThreadMethod;
  m1, m2: TThread;
  spins: Integer;
begin
  curOk := 0; termOnMain := 0; fotDone := 0; suspWork := 0; lateStartRan := 0;

  { CurrentThread on the main thread: a stable placeholder instance. }
  m1 := CurrentThread;
  m2 := CurrentThread;
  if (m1 <> nil) and (m1 = m2) then writeln('main current OK');

  { CurrentThread inside Execute + OnTerminate marshalled to main. }
  c := TCurWorker.Create(True);
  mt := @c.Terminated_;
  c.OnTerminate := mt;
  c.Start;
  while not c.Finished do CheckSynchronize;   { pump: OnTerminate needs main }
  c.WaitFor;
  c.Free;
  writeln('currentthread=', curOk, ' ontermmain=', termOnMain);

  { FreeOnTerminate: worker self-frees; the pump reaps its handle/stack. }
  f := TFotWorker.Create(True);
  f.FreeOnTerminate := True;
  f.Start;
  spins := 0;
  while (fotDone = 0) and (spins < 100000000) do spins := spins + 1;
  CheckSynchronize;                            { drain the reaper list }
  writeln('freeonterminate=', fotDone);

  { Suspend (self-park) / Resume from the main thread. }
  s := TSuspWorker.Create(False);
  while suspWork <> 1 do ;                     { worker reached the park }
  while not s.Suspended do ;                   { and is inside Suspend }
  s.Resume;
  s.WaitFor;
  writeln('suspend=', suspWork, ' suspended=', s.Suspended);
  s.Free;

  { Legacy Create(True) + Resume acts as Start. }
  l := TLateWorker.Create(True);
  l.Resume;
  l.WaitFor;
  writeln('latestart=', lateStartRan);
  l.Free;

  writeln('TTHREAD FINAL OK');
end.

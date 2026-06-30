program test_tthread;
{ M3: native TThread (x86-64). NT worker threads, each a TThread subclass whose
  Execute does K increments of a shared counter under a futex mutex. Created
  suspended, started together, joined via WaitFor. Final counter = NT*K proves
  the class plumbing (spawn / virtual Execute dispatch / join) all work. Builds on
  the M1/M2 PAL — libc-free. }
uses palthread, palsync, palthreadobj;

const
  NT = 4;
  K  = 100000;

var
  counter: Integer;
  m: TMutex;

type
  TWorker = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TWorker.Execute;
var
  j: Integer;
begin
  for j := 1 to K do
  begin
    MutexLock(m);
    counter := counter + 1;
    MutexUnlock(m);
  end;
end;

var
  w: array[0..NT-1] of TWorker;
  i, v: Integer;
begin
  MutexInit(m);
  counter := 0;

  for i := 0 to NT - 1 do
    w[i] := TWorker.Create(True);   { suspended }
  for i := 0 to NT - 1 do
    w[i].Start;                     { run together }
  for i := 0 to NT - 1 do
    w[i].WaitFor;

  v := counter;
  writeln('counter=', v, ' expected=', NT * K);
  if v = NT * K then writeln('TTHREAD OK') else writeln('TTHREAD FAIL');
end.

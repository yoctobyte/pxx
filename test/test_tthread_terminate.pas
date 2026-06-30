program test_tthread_terminate;
{ M3 follow-up: TThread cooperative cancellation (Terminate/Terminated) + ReturnValue
  (x86-64). The worker signals it is running, then spins until Terminated, then sets
  ReturnValue. Main waits for the run signal, calls Terminate, WaitFor, and checks
  the flags + result. Libc-free (M1/M2/M3 PAL). }
uses palthread, palsync, palthreadobj;

var
  running: Integer;     { worker -> 1 once it is executing (atomic publish) }

type
  TW = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TW.Execute;
var
  spin: Int64;
  ignore: Int64;
begin
  ignore := __pxxatomic_xchg(@running, 1);     { tell main we are running }
  spin := 0;
  { Self-qualified: unqualified property access inside a method is a known pxx gap
    (bug-unqualified-property-in-method) — Self.Terminated resolves fine. }
  while not Self.Terminated do                    { cooperative cancellation }
    spin := spin + 1;
  Self.ReturnValue := 42;
end;

var
  w: TW;
  ignore: Int64;
begin
  running := 0;
  w := TW.Create(True);
  w.Start;

  { wait until the worker is actually executing }
  while running = 0 do
    ignore := __pxxatomic_add(@running, 0);     { re-read via atomic (no opt assumptions) }

  w.Terminate;                                   { ask it to stop }
  w.WaitFor;                                     { join }

  writeln('terminated=', w.Terminated);
  writeln('finished=', w.Finished);
  writeln('returnvalue=', w.ReturnValue);
  if w.Terminated and w.Finished and (w.ReturnValue = 42) then
    writeln('TERMINATE OK')
  else
    writeln('TERMINATE FAIL');
end.

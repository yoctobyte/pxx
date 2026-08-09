{ The FPC threading surface, where FPC code actually looks for it.

  pxx has had a real native TThread for a while; what was missing was the NAMES
  and SHAPES, so every portable threaded source needed a {$IFDEF FPC} split in
  its uses line before it would build on both sides — which is the whole finding
  of compat-pascal-thread-api-surface-differs-from-fpc.

  Every expectation below is FPC's own output for the same program, measured:

    r := t.WaitFor                       ->  77   (FPC: function WaitFor: LongWord)
    BeginThread + WaitForThreadTerminate ->  55
    EndThread(88) early exit             ->  rc=88, the line after it NOT reached
    SizeOf(TThreadID)                    ->  8

  `uses cthreads` is here for its own sake: on FPC it installs the C thread
  manager and portable sources open with it, so it has to exist and compile.
  Failing to keep it EMPTY would be its own regression — a program that inherited
  the line from a portable header must not thereby acquire the thread runtime. }
{$threadsafe on}
program lib_fpc_thread_surface;

uses cthreads, palthreadobj, sysutils;

var
  failures: Integer;
  reached:  Integer;

procedure Check(ok: Boolean; const what: string);
begin
  if not ok then
  begin
    writeln('FAIL: ', what);
    failures := failures + 1;
  end;
end;

type
  TW = class(TThread)
  public
    procedure Execute; override;
  end;

procedure TW.Execute;
begin
  ReturnValue := 77;
end;

{ FPC's low-level body shape: takes the opaque arg, returns the thread result. }
function Body(p: Pointer): Int64;
begin
  Result := 55;
end;

function EarlyBody(p: Pointer): Int64;
begin
  EndThread(88);
  reached := 1;              { must NOT run — EndThread does not return }
  Result := 0;
end;

function ArgBody(p: Pointer): Int64;
begin
  Result := PInteger(p)^ * 2;
end;

var
  t:   TW;
  r:   LongWord;
  id:  TThreadID;
  rc:  Int64;
  arg: Integer;
begin
  failures := 0;
  reached := 0;

  { --- TThread.WaitFor is a FUNCTION returning ReturnValue, like FPC's --- }
  t := TW.Create(True);
  t.FreeOnTerminate := False;
  t.Start;
  r := t.WaitFor;
  Check(r = 77, 'WaitFor returns ReturnValue');
  Check(t.ReturnValue = 77, 'ReturnValue readable after WaitFor');
  t.WaitFor;                 { idempotent, and discardable as a statement }
  t.Free;

  { --- BeginThread / WaitForThreadTerminate / CloseThread --- }
  Check(SizeOf(TThreadID) = 8, 'SizeOf(TThreadID) = 8');
  id := BeginThread(@Body, nil);
  Check(id > 0, 'BeginThread returns a thread id');
  rc := WaitForThreadTerminate(id, 0);
  Check(rc = 55, 'WaitForThreadTerminate returns the body result');
  CloseThread(id);
  { after CloseThread the id is no longer known — must not hang or crash }
  Check(WaitForThreadTerminate(id, 0) = 0, 'wait on a closed id answers 0');

  { --- the opaque argument reaches the body --- }
  arg := 21;
  id := BeginThread(@ArgBody, @arg);
  Check(WaitForThreadTerminate(id, 0) = 42, 'BeginThread passes its argument');
  CloseThread(id);

  { --- EndThread ends the thread THERE, with that result --- }
  id := BeginThread(@EarlyBody, nil);
  rc := WaitForThreadTerminate(id, 0);
  Check(rc = 88, 'EndThread sets the thread result');
  Check(reached = 0, 'EndThread does not return to its caller');
  CloseThread(id);

  if failures = 0 then writeln('FPCTHREAD OK')
  else writeln('FPCTHREAD ', failures, ' FAILURES');
end.

{ TThread reached through `uses Classes`, the way FPC and Delphi code writes it.

  This is item 1 of compat-pascal-thread-api-surface-differs-from-fpc, and the
  point is the USES CLAUSE, not the threading — every thread behaviour here is
  already covered by lib_fpc_thread_surface.pas, which reaches palthreadobj
  directly. What this file proves is that a source with FPC's own uses line and
  no {$IFDEF FPC} split compiles.

  The uses clause below is exactly what an FPC program writes, and this exact
  source (minus the {$threadsafe on} line, which FPC does not need) compiles on
  FPC 3.2.2 and prints the SAME two numbers — verified, not assumed.

  WHY IT IS CONDITIONAL, since a future reader will want to make it
  unconditional: classes reaches TThread through palthreadobj -> palthread,
  which contains __pxxclone, and the parser refuses that identifier unless the
  thread-safe runtime is selected. Unconditional, this file's convenience would
  cost every `uses classes` program in existence the ability to compile without
  --threadsafe. So classes gates the declaration on PXX_THREADSAFE, and the
  non-threaded half of that bargain is asserted by every OTHER classes test in
  lib-test, all of which build without the flag. }
{$threadsafe on}
program lib_classes_tthread;

uses cthreads, Classes, SysUtils, SyncObjs;

type
  TBumper = class(TThread)
  public
    procedure Execute; override;
  end;

var
  Counter: Integer;
  Lock: TCriticalSection;

procedure TBumper.Execute;
var i: Integer;
begin
  for i := 1 to 2000 do
  begin
    Lock.Acquire;
    try Counter := Counter + 1; finally Lock.Release; end;
  end;
  ReturnValue := 99;
end;

var
  t: array[0..3] of TBumper;
  k: Integer;
  r: LongWord;
  failures: Integer;
begin
  failures := 0;
  Lock := TCriticalSection.Create;
  Counter := 0;
  for k := 0 to 3 do
  begin
    t[k] := TBumper.Create(True);
    t[k].FreeOnTerminate := False;
    t[k].Start;
  end;
  r := 0;
  for k := 0 to 3 do r := t[k].WaitFor;
  if Counter <> 8000 then
  begin
    writeln('FAIL: counter=', Counter, ' want 8000');
    failures := failures + 1;
  end;
  if r <> 99 then
  begin
    writeln('FAIL: WaitFor=', r, ' want 99');
    failures := failures + 1;
  end;
  for k := 0 to 3 do t[k].Free;
  Lock.Free;

  if failures = 0 then writeln('CLASSESTHREAD OK')
  else writeln('CLASSESTHREAD ', failures, ' FAILURES');
end.

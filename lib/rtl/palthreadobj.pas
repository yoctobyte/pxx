unit palthreadobj;
{ M3 native Pascal TThread (meta-multithreading). The "threads just work" surface:
  subclass TThread, override Execute, Start, WaitFor. FPC-flavoured subset, built
  entirely on the libc-free M1/M2 PAL (palthread + palsync) — no libc, no RTL
  thread manager.

  A spawned thread runs ThreadObjLauncher(Self), which virtual-dispatches into the
  subclass's Execute and marks the thread finished on return.

  NOTE (shared-state caveat, see the multithreading audit): the heap allocator is
  only thread-safe under --threadsafe / {$threadsafe on}. An Execute that allocates
  (managed strings, GetMem, objects) concurrently needs that flag; an Execute that
  only touches preallocated state + sync primitives is safe without it.

  x86-64 first (the PAL it stands on is x86-64 today). }

interface

uses palthread;

type
  TThread = class
  private
    FHandle:   TThreadHandle;
    FStarted:  Boolean;
    FFinished: Boolean;
  protected
    { Override with the thread body. Runs on the spawned OS thread. }
    procedure Execute; virtual; abstract;
  public
    { CreateSuspended = True: build but do not run yet (call Start later).
      False: spawn immediately (the FPC footgun applies — the OS thread may run
      Execute before a subclass constructor finishes its own init). }
    constructor Create(CreateSuspended: Boolean);

    { Spawn the OS thread (no-op if already started). }
    procedure Start;
    { Block until the thread's Execute returns (no-op if never started). Call
      before freeing the instance — there is no auto-join destructor yet. }
    procedure WaitFor;

    { Kernel thread id (0 until started). }
    function ThreadID: Int64;

    property Finished: Boolean read FFinished;
  end;

implementation

{ File-level trampoline: PalThreadCreate hands us the instance as the opaque arg. }
procedure ThreadObjLauncher(arg: Pointer);
var
  t: TThread;
begin
  t := TThread(arg);
  t.Execute;
  t.FFinished := True;
end;

constructor TThread.Create(CreateSuspended: Boolean);
begin
  FStarted := False;
  FFinished := False;
  if not CreateSuspended then Start;
end;

procedure TThread.Start;
begin
  if FStarted then Exit;
  FStarted := True;
  PalThreadCreate(FHandle, @ThreadObjLauncher, Pointer(Self), 0);
end;

procedure TThread.WaitFor;
begin
  if FStarted then PalThreadJoin(FHandle);
end;

function TThread.ThreadID: Int64;
begin
  Result := FHandle.Tid;
end;

end.

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

uses palthread, palsync;

type
  { A method pointer (TMethod shape): built by `@obj.Method` / `@Self.Method`.
    Code = method entry, Data = instance (passed as Self on invoke). }
  TThreadMethod = record
    Code: Pointer;
    Data: Pointer;
  end;

type
  TThread = class
  private
    FHandle:      TThreadHandle;
    FStarted:     Boolean;
    FFinished:    Boolean;
    FTerminated:  Boolean;
    FReturnValue: Integer;
  protected
    { Override with the thread body. Runs on the spawned OS thread. }
    procedure Execute; virtual; abstract;
  public
    { CreateSuspended = True: build but do not run yet (call Start later).
      False: spawn immediately (the FPC footgun applies — the OS thread may run
      Execute before a subclass constructor finishes its own init). }
    constructor Create(CreateSuspended: Boolean);

    { Auto-join destructor (FPC semantics): a still-running thread is
      Terminate'd (cooperative) and WaitFor'd before the instance dies, so
      `t.Free` alone is always safe. Virtual — descendants declare
      `destructor Destroy; override;` and call `inherited Destroy`. }
    destructor Destroy; virtual;

    { Spawn the OS thread (no-op if already started). }
    procedure Start;
    { Block until the thread's Execute returns (no-op if never started).
      Idempotent; also called by the destructor (auto-join). }
    procedure WaitFor;

    { Run m (`@Self.SomeMethod`) on the MAIN thread and block until it has run
      there. The main thread must pump CheckSynchronize (console programs have
      no event loop — same contract as FPC). Called ON the main thread it just
      invokes m directly. }
    procedure Synchronize(m: TThreadMethod);

    { Fire-and-forget variant: enqueue m for the main thread's next
      CheckSynchronize and return immediately (invoked directly when called on
      the main thread, like FPC). }
    procedure Queue(m: TThreadMethod);

    { Kernel thread id (0 until started). }
    function ThreadID: Int64;

    { Cooperative cancellation (FPC pattern): Terminate sets the Terminated flag;
      a well-behaved Execute polls `Terminated` and returns early. It does NOT
      forcibly kill the thread. }
    procedure Terminate;

    property Terminated: Boolean read FTerminated;
    property Finished: Boolean read FFinished;
    { Thread result — Execute assigns it, the joiner reads it after WaitFor. }
    property ReturnValue: Integer read FReturnValue write FReturnValue;
  end;

{ Drain the Synchronize/Queue backlog. Call it periodically FROM THE MAIN
  THREAD (e.g. inside the main loop that waits for workers). Returns True if
  at least one queued call ran. }
function CheckSynchronize: Boolean;

{ Kernel tid of the thread that initialized this unit (the main thread). }
function MainThreadID: Int64;

implementation

{ ---- Synchronize/Queue machinery -------------------------------------------
  A mutex-guarded singly-linked list of pending main-thread calls. Synchronize
  entries live on the CALLER's stack (it blocks until done, so the address is
  stable) and carry a futex word the main thread sets+wakes after invoking.
  Queue entries are heap-allocated (caller returns immediately) and freed by
  CheckSynchronize after the call. Requires --threadsafe (enforced at the
  __pxxclone compile gate), so GetMem/FreeMem here are safe from any thread. }

type
  TSyncInvoke = procedure(inst: Pointer);
  PSyncEntry = ^TSyncEntry;
  TSyncEntry = record
    Method:    TThreadMethod;
    DoneWord:  Integer;     { futex: 0 = pending, 1 = executed (Synchronize) }
    IsQueued:  Boolean;     { True = heap-owned fire-and-forget (Queue) }
    NextEntry: PSyncEntry;
  end;

var
  SyncLock: TMutex;         { zeroed BSS record = unlocked, no init needed }
  SyncHead: PSyncEntry;
  SyncTail: PSyncEntry;
  MainTid:  Int64;

procedure SyncInvokeMethod(m: TThreadMethod);
var
  f: TSyncInvoke;
begin
  f := TSyncInvoke(m.Code);
  f(m.Data);
end;

procedure SyncEnqueue(e: PSyncEntry);
begin
  e^.NextEntry := nil;
  MutexLock(SyncLock);
  if SyncTail = nil then SyncHead := e else SyncTail^.NextEntry := e;
  SyncTail := e;
  MutexUnlock(SyncLock);
end;

function CheckSynchronize: Boolean;
var
  e: PSyncEntry;
begin
  Result := False;
  while True do
  begin
    MutexLock(SyncLock);
    e := SyncHead;
    if e <> nil then
    begin
      SyncHead := e^.NextEntry;
      if SyncHead = nil then SyncTail := nil;
    end;
    MutexUnlock(SyncLock);
    if e = nil then Exit;
    Result := True;
    SyncInvokeMethod(e^.Method);
    if e^.IsQueued then
      FreeMem(e)
    else
    begin
      e^.DoneWord := 1;
      PalFutexWake(@e^.DoneWord, 1);
    end;
  end;
end;

function MainThreadID: Int64;
begin
  Result := MainTid;
end;

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
  FTerminated := False;
  FReturnValue := 0;
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

procedure TThread.Terminate;
begin
  { one-way flag, observed by Execute via the Terminated property; plain store is
    fine for cooperative cancellation (eventual cross-core visibility). }
  FTerminated := True;
end;

destructor TThread.Destroy;
begin
  if FStarted and (not FFinished) then Terminate;
  WaitFor;
end;

procedure TThread.Synchronize(m: TThreadMethod);
var
  e: TSyncEntry;   { caller-stack entry: stable address, we block until done }
begin
  if PalThreadSelf = MainTid then
  begin
    SyncInvokeMethod(m);
    Exit;
  end;
  e.Method := m;
  e.DoneWord := 0;
  e.IsQueued := False;
  SyncEnqueue(@e);
  while e.DoneWord = 0 do
    PalFutexWait(@e.DoneWord, 0);
end;

procedure TThread.Queue(m: TThreadMethod);
var
  e: PSyncEntry;
begin
  if PalThreadSelf = MainTid then
  begin
    SyncInvokeMethod(m);
    Exit;
  end;
  GetMem(e, SizeOf(TSyncEntry));
  e^.Method := m;
  e^.DoneWord := 0;
  e^.IsQueued := True;
  SyncEnqueue(e);
end;

initialization
  MainTid := PalThreadSelf;
  SyncHead := nil;
  SyncTail := nil;
  MutexInit(SyncLock);
end.

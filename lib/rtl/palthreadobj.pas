{ SPDX-License-Identifier: Zlib }
unit palthreadobj;
{ M3 native Pascal TThread (meta-multithreading). The "threads just work" surface:
  subclass TThread, override Execute, Start, WaitFor. FPC-flavoured subset, built
  entirely on the libc-free M1/M2 PAL (palthread + palsync) — no libc, no RTL
  thread manager.

  A spawned thread runs ThreadObjLauncher(Self), which virtual-dispatches into the
  subclass's Execute, fires OnTerminate (marshalled to the main thread), marks the
  thread finished, and honours FreeOnTerminate.

  NOTE (shared-state caveat, see the multithreading audit): the heap allocator is
  only thread-safe under --threadsafe / {$threadsafe on}. An Execute that allocates
  (managed strings, GetMem, objects) concurrently needs that flag; an Execute that
  only touches preallocated state + sync primitives is safe without it.

  x86-64 first (the PAL it stands on is x86-64 today). }

interface

uses palfutex, palthread, palsync;

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
    { The thread handle lives on the HEAP, not inline: the kernel futex-writes
      the handle's TidWord at thread exit (CLONE_CHILD_CLEARTID), so its address
      must outlive the thread even when FreeOnTerminate destroys the instance
      from inside the thread. Allocated by Start; released after join (or by
      the CheckSynchronize reaper for self-freed threads). }
    FHandlePtr:    PThreadHandle;
    FStarted:      Boolean;
    FFinished:     Boolean;
    FTerminated:   Boolean;
    FFreeOnTerm:   Boolean;
    FSuspended:    Boolean;
    FSuspendGate:  Integer;   { futex word: 0 = parked, 1 = released }
    FReturnValue:  Integer;
    FOnTerminate:  TThreadMethod;
    FNextThread:   TThread;   { CurrentThread registry chain }
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
    { Block until the thread's Execute returns, then hand back its ReturnValue —
      `r := t.WaitFor` is the FPC idiom and this matches it (FPC: `function
      WaitFor: LongWord`). No-op if never started, or when called from the
      thread itself, since a self-join would deadlock; both of those answer
      with whatever ReturnValue currently holds. Idempotent; also called by the
      destructor (auto-join), where the result is discarded. }
    function WaitFor: LongWord;

    { Run m (`@Self.SomeMethod`) on the MAIN thread and block until it has run
      there. The main thread must pump CheckSynchronize (console programs have
      no event loop — same contract as FPC). Called ON the main thread it just
      invokes m directly. }
    procedure Synchronize(const m: TThreadMethod);

    { Fire-and-forget variant: enqueue m for the main thread's next
      CheckSynchronize and return immediately (invoked directly when called on
      the main thread, like FPC). }
    procedure Queue(const m: TThreadMethod);

    { Kernel thread id (0 until started). }
    function ThreadID: Int64;

    { Cooperative cancellation (FPC pattern): Terminate sets the Terminated flag;
      a well-behaved Execute polls `Terminated` and returns early. It does NOT
      forcibly kill the thread. }
    procedure Terminate;

    { Cooperative suspend: callable only FROM the thread itself (the async
      form FPC deprecated is unsafe by construction — there is no safe point).
      Parks on a futex until Resume. Called from any other thread it is a
      no-op. }
    procedure Suspend;

    { Release a Suspend'ed thread. On a never-started thread (legacy
      Create(True) pattern) Resume doubles as Start, like classic FPC/Delphi. }
    procedure Resume;

    property Terminated: Boolean read FTerminated;
    property Finished: Boolean read FFinished;
    property Suspended: Boolean read FSuspended;
    { Thread result — Execute assigns it, the joiner reads it after WaitFor. }
    property ReturnValue: Integer read FReturnValue write FReturnValue;
    { Free the instance from the thread itself when Execute returns (after
      OnTerminate). The thread's kernel stack is reclaimed by the next
      CheckSynchronize on the main thread (or at process exit). }
    property FreeOnTerminate: Boolean read FFreeOnTerm write FFreeOnTerm;
    { Fired after Execute returns, marshalled to the MAIN thread via
      Synchronize — the main thread must be pumping CheckSynchronize or the
      worker blocks. Parameterless method pointer (`@Self.M`), not FPC's
      TNotifyEvent(Sender) — Data already carries the receiver. }
    property OnTerminate: TThreadMethod read FOnTerminate write FOnTerminate;
  end;

{ ---- FPC's low-level thread API -------------------------------------------
  System-unit names in FPC, so portable sources call them with no uses line;
  here they need `uses palthreadobj` until they are reachable the way FPC's are
  (the same wart as bug-a-interlocked-family-needs-a-uses-clause-unlike-fpc).

  They live in M3 rather than in palthread itself so the layering stays one-way:
  the registry that makes WaitForThreadTerminate able to hand back a body's
  result needs a mutex, and palsync (M2) is built ON palthread (M1). Putting an
  FPC-surface layer here keeps M1 raw. }
type
  { FPC: PtrUInt, 8 bytes on 64-bit. Here it carries the kernel tid, the same
    value TThread.ThreadID reports, so the two APIs agree about identity —
    FPC's is a pthread_t, which is opaque, so nothing portable can tell. }
  TThreadID = Int64;

  { FPC's thread body shape: takes the opaque argument, returns the thread's
    result. `function(p: Pointer): PtrInt`. }
  TThreadFunc = function(p: Pointer): Int64;

{ Spawn f(p) on a new thread. Returns its TThreadID, or 0 on failure. The
  thread's result is kept until CloseThread, so WaitForThreadTerminate can
  return it after the thread is gone. }
function BeginThread(f: TThreadFunc; p: Pointer): TThreadID;

{ End the CALLING thread with the given result. Returning from the body does
  the same thing; this is the early-exit form. }
procedure EndThread(exitCode: Int64);

{ Block until the thread ends and return its result. FPC's timeoutMs is
  accepted and IGNORED — the underlying join is unbounded, and silently
  returning early would be a wrong answer rather than a missing feature, so a
  caller that passes a timeout gets a correct (late) result rather than a
  plausible wrong one. 0 means "no timeout" in FPC and is the only value with
  identical behaviour here. }
function WaitForThreadTerminate(id: TThreadID; timeoutMs: Int64): Int64;

{ Release the bookkeeping for a finished thread. Safe to call once per
  BeginThread; after it, the id is no longer known. }
procedure CloseThread(id: TThreadID);

{ Drain the Synchronize/Queue backlog (and reap the handles/stacks of
  FreeOnTerminate threads that have since exited). Call it periodically FROM
  THE MAIN THREAD (e.g. inside the main loop that waits for workers). Returns
  True if at least one queued call ran. }
function CheckSynchronize: Boolean;

{ Kernel tid of the thread that initialized this unit (the main thread). }
function MainThreadID: Int64;

{ The TThread instance of the calling thread. On the main thread returns a
  lazily-created placeholder instance (never started; its Execute never runs),
  mirroring FPC's TExternalThread. Unit-level rather than the FPC class
  property `TThread.CurrentThread` (pxx has no class-static properties yet). }
function CurrentThread: TThread;

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

  { A FreeOnTerminate thread's heap handle, parked until the main thread can
    join it (frees the 1 MiB child stack) and release the handle block. }
  PReapNode = ^TReapNode;
  TReapNode = record
    Handle:   PThreadHandle;
    NextNode: PReapNode;
  end;

var
  SyncLock: TMutex;         { zeroed BSS record = unlocked, no init needed }
  SyncHead: PSyncEntry;
  SyncTail: PSyncEntry;
  MainTid:  Int64;
  ReapHead: PReapNode;      { guarded by SyncLock too (same pump drains it) }
  RegHead:  TThread;        { CurrentThread registry, guarded by SyncLock }
  MainThreadObj: TThread;   { lazy placeholder for CurrentThread on main }

procedure SyncInvokeMethod(const m: TThreadMethod);
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
  r, rn: PReapNode;
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
    if e = nil then Break;
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

  { Reap exited FreeOnTerminate threads: join (releases the child stack; the
    thread exits within a few instructions of parking its handle, so any wait
    here is momentary) and release the heap handle. }
  MutexLock(SyncLock);
  r := ReapHead;
  ReapHead := nil;
  MutexUnlock(SyncLock);
  while r <> nil do
  begin
    PalThreadJoin(r^.Handle^);
    FreeMem(r^.Handle);
    rn := r^.NextNode;
    FreeMem(r);
    r := rn;
  end;
end;

function MainThreadID: Int64;
begin
  Result := MainTid;
end;

function CurrentThread: TThread;
var
  tid: Int64;
  t: TThread;
begin
  tid := PalThreadSelf;
  if tid = MainTid then
  begin
    if MainThreadObj = nil then
      MainThreadObj := TThread.Create(True);   { placeholder; never started }
    Result := MainThreadObj;
    Exit;
  end;
  Result := nil;
  MutexLock(SyncLock);
  t := RegHead;
  while t <> nil do
  begin
    if (t.FHandlePtr <> nil) and (t.FHandlePtr^.Tid = tid) then
    begin
      Result := t;
      Break;
    end;
    t := t.FNextThread;
  end;
  MutexUnlock(SyncLock);
end;

procedure RegisterThread(t: TThread);
begin
  MutexLock(SyncLock);
  t.FNextThread := RegHead;
  RegHead := t;
  MutexUnlock(SyncLock);
end;

procedure UnregisterThread(t: TThread);
var
  p: TThread;
begin
  MutexLock(SyncLock);
  if RegHead = t then
    RegHead := t.FNextThread
  else
  begin
    p := RegHead;
    while p <> nil do
    begin
      if p.FNextThread = t then
      begin
        p.FNextThread := t.FNextThread;
        Break;
      end;
      p := p.FNextThread;
    end;
  end;
  MutexUnlock(SyncLock);
end;

{ Park a self-freed thread's handle for the main pump to join + release. }
procedure ReaperPush(h: PThreadHandle);
var
  n: PReapNode;
begin
  GetMem(n, SizeOf(TReapNode));
  n^.Handle := h;
  MutexLock(SyncLock);
  n^.NextNode := ReapHead;
  ReapHead := n;
  MutexUnlock(SyncLock);
end;

{ File-level trampoline: PalThreadCreate hands us the instance as the opaque arg. }
procedure ThreadObjLauncher(arg: Pointer);
var
  t: TThread;
  freeSelf: Boolean;
  mt: TThreadMethod;
begin
  t := TThread(arg);
  { The parent stores the child tid into FHandlePtr^.Tid only after __pxxclone
    returns — but this thread can reach Execute first. Every child-side
    tid-identity check (CurrentThread's registry match, Suspend's own-thread
    guard, WaitFor/Destroy self-call guards) then compares against a stale 0:
    CurrentThread returned nil ~1% of runs, and a lost Suspend guard skips the
    park entirely (main's `while not Suspended` spins forever). Writing our own
    tid here is program-order-safe for all child-side reads; the parent's later
    store writes the identical value, so the duplicate is benign even where an
    Int64 store tears (32-bit). Full contract + rejected alternatives
    (handshake, CLONE_CHILD_SETTID): devdocs/dev/threading.md "Tid identity"
    and the RACE CONTRACT on TThreadHandle in palthread.pas. }
  t.FHandlePtr^.Tid := PalThreadSelf;
  t.Execute;
  { Field-wise copy into a local before the call: reading the record FIELD as
    a value trips the i386 backend's load-through-pointer gap; two pointer
    loads are portable, and the local passes by const-ref. }
  mt.Code := t.FOnTerminate.Code;
  mt.Data := t.FOnTerminate.Data;
  if mt.Code <> nil then
    t.Synchronize(mt);
  freeSelf := t.FFreeOnTerm;
  t.FFinished := True;
  if freeSelf then
    t.Free;    { Destroy sees the self-call: skips the join, parks the handle }
end;

constructor TThread.Create(CreateSuspended: Boolean);
begin
  FTerminated := False;
  FReturnValue := 0;
  FStarted := False;
  FFinished := False;
  FSuspended := False;
  FSuspendGate := 0;
  FFreeOnTerm := False;
  FOnTerminate.Code := nil;
  FOnTerminate.Data := nil;
  FHandlePtr := nil;
  FNextThread := nil;
  if not CreateSuspended then Start;
end;

procedure TThread.Start;
begin
  if FStarted then Exit;
  FStarted := True;
  GetMem(FHandlePtr, SizeOf(TThreadHandle));
  RegisterThread(Self);
  PalThreadCreate(FHandlePtr^, @ThreadObjLauncher, Pointer(Self), 0);
end;

function TThread.WaitFor: LongWord;
begin
  if FStarted and (FHandlePtr <> nil)
     and (PalThreadSelf <> FHandlePtr^.Tid) then  { self-join would deadlock }
    PalThreadJoin(FHandlePtr^);
  { Read AFTER the join: that is the whole point of returning it — Execute's
    store to ReturnValue happens-before the thread exit the join waits on. }
  Result := LongWord(FReturnValue);
end;

function TThread.ThreadID: Int64;
begin
  if FHandlePtr = nil then
    Result := 0
  else
    Result := FHandlePtr^.Tid;
end;

procedure TThread.Terminate;
begin
  { one-way flag, observed by Execute via the Terminated property; plain store is
    fine for cooperative cancellation (eventual cross-core visibility). }
  FTerminated := True;
end;

procedure TThread.Suspend;
begin
  if (FHandlePtr = nil) or (PalThreadSelf <> FHandlePtr^.Tid) then Exit;
  FSuspended := True;
  while FSuspendGate = 0 do
    PalFutexWait(@FSuspendGate, 0);
  FSuspendGate := 0;    { consume the release; the next Suspend parks again }
  FSuspended := False;
end;

procedure TThread.Resume;
begin
  if not FStarted then
  begin
    Start;              { legacy Create(True) + Resume }
    Exit;
  end;
  FSuspendGate := 1;
  PalFutexWake(@FSuspendGate, 1);
end;

destructor TThread.Destroy;
begin
  if FStarted and (not FFinished) then Terminate;
  WaitFor;
  UnregisterThread(Self);
  if FHandlePtr <> nil then
  begin
    if PalThreadSelf = FHandlePtr^.Tid then
      ReaperPush(FHandlePtr)   { FreeOnTerminate: main pump joins + frees it }
    else
      FreeMem(FHandlePtr);     { already joined by WaitFor above }
  end;
end;

procedure TThread.Synchronize(const m: TThreadMethod);
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

procedure TThread.Queue(const m: TThreadMethod);
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

{ ---- FPC's low-level thread API --------------------------------------------
  BeginThread's body has FPC's shape (returns a result); PalThreadCreate's has
  the PAL's (returns nothing). The bridge is a heap SLOT per thread, passed as
  the PAL's opaque arg: the launcher finds its own slot with no lookup, runs the
  body, and parks the result there.

  The slot is what makes WaitForThreadTerminate answerable AFTER the thread is
  gone — the result cannot live in the thread, and the tid stops identifying
  anything once the kernel reuses it. So the slot outlives the thread and
  CloseThread is what releases it, which is exactly why FPC has CloseThread at
  all. }
type
  PThreadSlot = ^TThreadSlot;
  TThreadSlot = record
    Handle:   TThreadHandle;
    Body:     TThreadFunc;
    Arg:      Pointer;
    Res:      Int64;
    Tid:      Int64;
    NextSlot: PThreadSlot;
  end;

var
  SlotHead: PThreadSlot;    { guarded by SyncLock }

procedure BeginThreadLauncher(arg: Pointer);
var
  s: PThreadSlot;
  f: TThreadFunc;
begin
  s := PThreadSlot(arg);
  { Same tid-identity rule as ThreadObjLauncher: the parent's store of the tid
    races our start, so write our own before anything can look for us. }
  s^.Tid := PalThreadSelf;
  f := s^.Body;
  s^.Res := f(s^.Arg);
end;

{ Match on EITHER tid field, because the two sides of this API learn the tid at
  different moments and neither ordering can be assumed (the RACE CONTRACT on
  TThreadHandle in palthread.pas). Handle.Tid is written by the PARENT when
  __pxxclone returns, so it is the one a joiner can rely on; s^.Tid is written by
  the CHILD as its first act, so it is the one the child itself can rely on when
  EndThread has to find its own slot. Keying on only the child's field made
  WaitForThreadTerminate return 0 whenever the joiner beat the child's first
  instruction — which it does whenever the box is busy, and did not on the quick
  standalone probe that "passed". Ids are always > 0, so a half-filled slot's 0
  cannot be matched by accident; id <= 0 is refused outright. }
function FindSlot(id: TThreadID): PThreadSlot;
var s: PThreadSlot;
begin
  Result := nil;
  if id <= 0 then Exit;
  s := SlotHead;
  while s <> nil do
  begin
    if (s^.Handle.Tid = id) or (s^.Tid = id) then
    begin
      Result := s;
      Break;
    end;
    s := s^.NextSlot;
  end;
end;

function BeginThread(f: TThreadFunc; p: Pointer): TThreadID;
var
  s, prev: PThreadSlot;
  rc: Integer;
begin
  GetMem(s, SizeOf(TThreadSlot));
  s^.Body := f;
  s^.Arg := p;
  s^.Res := 0;
  s^.Tid := 0;
  { Linked in BEFORE the spawn: the child writes s^.Tid as its first act, and a
    joiner that raced in between would otherwise not find a slot that exists. }
  MutexLock(SyncLock);
  s^.NextSlot := SlotHead;
  SlotHead := s;
  MutexUnlock(SyncLock);
  rc := PalThreadCreate(s^.Handle, @BeginThreadLauncher, Pointer(s), 0);
  if rc <> 0 then
  begin
    { Unlink by identity, not by head: another BeginThread may have pushed in
      front of us between the link and the failed clone. }
    MutexLock(SyncLock);
    if SlotHead = s then SlotHead := s^.NextSlot
    else
    begin
      prev := SlotHead;
      while (prev <> nil) and (prev^.NextSlot <> s) do prev := prev^.NextSlot;
      if prev <> nil then prev^.NextSlot := s^.NextSlot;
    end;
    MutexUnlock(SyncLock);
    FreeMem(s);
    Result := 0;
    Exit;
  end;
  Result := s^.Handle.Tid;
end;

procedure EndThread(exitCode: Int64);
var
  s: PThreadSlot;
  tid: Int64;
begin
  tid := PalThreadSelf;
  MutexLock(SyncLock);
  s := FindSlot(tid);
  if s <> nil then s^.Res := exitCode;
  MutexUnlock(SyncLock);
  PalThreadExit;
end;

function WaitForThreadTerminate(id: TThreadID; timeoutMs: Int64): Int64;
var
  s: PThreadSlot;
begin
  Result := 0;
  MutexLock(SyncLock);
  s := FindSlot(id);
  MutexUnlock(SyncLock);
  if s = nil then Exit;                    { unknown or already closed }
  if PalThreadSelf <> id then              { a self-join would deadlock }
    PalThreadJoin(s^.Handle);
  Result := s^.Res;
end;

procedure CloseThread(id: TThreadID);
var
  s, prev: PThreadSlot;
begin
  MutexLock(SyncLock);
  s := SlotHead;
  prev := nil;
  if id > 0 then
    while s <> nil do
    begin
      if (s^.Handle.Tid = id) or (s^.Tid = id) then Break;
      prev := s;
      s := s^.NextSlot;
    end
  else
    s := nil;
  if s <> nil then
  begin
    if prev = nil then SlotHead := s^.NextSlot else prev^.NextSlot := s^.NextSlot;
  end;
  MutexUnlock(SyncLock);
  if s = nil then Exit;
  { Join before releasing: the handle lives IN the slot, and the kernel clears
    its TidWord at thread exit, so freeing an unjoined slot hands the kernel a
    dangling write. PalThreadJoin is idempotent once joined. }
  if PalThreadSelf <> id then PalThreadJoin(s^.Handle);
  FreeMem(s);
end;

initialization
  SlotHead := nil;
  MainTid := PalThreadSelf;
  SyncHead := nil;
  SyncTail := nil;
  ReapHead := nil;
  RegHead := nil;
  MainThreadObj := nil;
  MutexInit(SyncLock);
end.

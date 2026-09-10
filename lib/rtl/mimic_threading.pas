{ SPDX-License-Identifier: Zlib }
unit mimic_threading;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `threading` module — Thread, Event and Lock, bound onto the RTL's own
  clone-based thread PAL.

  `import threading` RESOLVES here through the NilPy import resolver's `mimic_`
  fallback, so no file in the tree carries the stdlib's name and `--no-shims`
  can turn the substitution into an error. See devdocs/dev/python-compat-tiers.md.

  ## This is a BINDING job, and that is why it is a ticket rather than a wish

  Everything underneath already exists and is tested:

    palthread   PalThreadCreate / PalThreadJoin / PalThreadSelf  (clone, mmap'd
                stack, CLONE_PARENT_SETTID|CHILD_CLEARTID join handshake)
    palfutex    PalFutexWait / PalFutexWake / PalFutexWaitTimeout
    palsync     TMutex, TEvent, TCondVar — futex-backed, no libc

  What was missing was the Python SHAPE: a Thread that takes a callable rather
  than a subclass override, an Event whose `wait` takes a timeout and RETURNS
  the flag, and a `join(timeout=)` that can give up. Each of those is a real
  gap in the layer below, and each is filled here rather than pushed down,
  because they are Python's semantics and not the PAL's.

  ## --threadsafe is REQUIRED and the error says so before you get here

  `__pxxclone` refuses to compile without `--threadsafe` / `{$threadsafe on}`:
  the default heap, ARC and console-I/O runtime is not thread-safe, and a
  Python thread allocates on its first statement. So a program that imports
  this unit and is built without the flag fails at COMPILE time, in
  palthread.pas, with a message that names the flag. That is the right failure
  and it is not silent — but it names a Pascal file for a Python program, which
  is why the NilPy driver should imply the flag from the import. Until it does,
  build with --threadsafe.

  ## `daemon=True` is FREE, and that was measured rather than assumed

  2026-09-10, compiler `69c84acb1501`: a program that spawns a thread and
  returns from main WITHOUT joining exits immediately, rc=0, and the child's
  output never appears. The process teardown is exit_group, which takes every
  thread with it — which is precisely CPython's daemon semantics. So a daemon
  thread needs no bookkeeping at all, and all four Thread sites in the corpus
  this was written for are `daemon=True`.

  **A non-daemon thread is the one that needs work**, because CPython joins it
  at interpreter exit and we would otherwise kill it silently mid-flight —
  losing whatever it was doing, with no diagnostic. That is the worst shape a
  divergence can take, so non-daemon threads are registered here and joined in
  `finalization`. Untested against a corpus, because no corpus writes one; the
  test in test/test_nilpy_the_threading_module.npy is the only coverage.

  ## What is NOT here

  No `Condition`, `Semaphore`, `Barrier`, `local`, `current_thread`,
  `active_count`, `Timer`, or `Thread` subclassing with an `Execute`/`run`
  override. None is used by the corpus this was measured against, and each
  would be a claim with no test behind it. `Lock` IS here despite not being
  used, because `mimic_queue` needs one internally and a Python program that
  reaches a Queue across threads will reach for a Lock in the next line. }

interface

uses pylib, sysutils, palfutex, palthread, palsync, pythreadlive;

const
  { Python spells "no timeout" as None, and a Pascal parameter default must be
    a constant EXPRESSION -- a bare `-1.0` is not accepted as one here, so the
    sentinel is named. Negative because 0.0 is a legal Python timeout meaning
    "poll and return immediately", and a default that collides with a real
    value is a default that cannot be distinguished from one. }
  PY_NO_TIMEOUT = -1.0;

type
  { threading.Event — a manual-reset flag with a timed wait.

    `wait(timeout)` RETURNING the flag is load-bearing, not decoration: the
    corpus uses it as a poll interval (`if self._stop.wait(self.period): break`),
    so a wait that ignored the timeout would spin the CPU and one that returned
    nothing would never break. palsync's own EventWait has neither property —
    it blocks forever and returns nothing — which is why this is a wrapper and
    not an alias. }
  Event = class
  public
    { The futex word lives in the OBJECT, so its address is stable for the
      instance's life. palsync's contract asks exactly that. }
    FEv: TEvent;
    constructor Create;
    { `set` is not a reserved word in a method position in this dialect —
      verified before relying on it, because `array_` in mimic_array exists for
      exactly that reason and the two cases look alike. }
    procedure set;
    procedure clear;
    function is_set: Boolean;
    { timeout < 0 (the default) waits forever. Returns the flag AS OF the
      return, which is what CPython documents: True means signalled, False
      means the timeout ran out. }
    function wait(timeout: Double = PY_NO_TIMEOUT): Boolean;
  end;

  { threading.Lock — a plain futex mutex. `acquire`/`release`, and the two
    names CPython's context-manager protocol uses so `with lock:` works if the
    frontend grows it. }
  Lock = class
  public
    FM: TMutex;
    constructor Create;
    function acquire(blocking: Boolean = True): Boolean;
    procedure release;
    function locked: Boolean;
  end;

  { threading.Thread(target=, args=, daemon=, name=).

    ONE constructor with defaults, never overloads: a keyword argument does not
    bind on an OVERLOADED Pascal constructor, and every corpus site is
    all-keyword. The parameter NAMES are the Python kwarg names because a
    keyword binds by the Pascal parameter's name — mimic_queue records the same
    constraint, having been refused for calling its parameter `n`. }
  Thread = class
  public
    { Public because CPython exposes them as attributes and real code reads
      `t.name` and `t.daemon`. }
    name: AnsiString;
    daemon: Boolean;
    FTarget: Variant;
    FArgs: Variant;
    { The handle is on the HEAP and not inline: the kernel futex-writes TidWord
      at thread exit (CLONE_CHILD_CLEARTID), so its address must outlive the
      thread even if the instance does not. palthread.pas states this contract
      on TThreadHandle and palthreadobj obeys it the same way. }
    FHandlePtr: PThreadHandle;
    FStarted: Boolean;
    FJoined: Boolean;
    constructor Create(target: Variant = 0; args: Variant = 0;
                       daemon: Boolean = False; name: AnsiString = '');
    procedure start;
    { timeout < 0 (the default) waits forever, which is CPython's `join()`.
      A join that TIMES OUT is not an error in Python — it returns and the
      caller is expected to ask `is_alive()`. The corpus joins with
      `timeout=2.0` at shutdown and never asks, which is the whole point of
      giving up. }
    function join(timeout: Double = PY_NO_TIMEOUT): Variant;
    function is_alive: Boolean;
  end;

implementation

const
  NS_PER_S = 1000 * 1000 * 1000;

{ ---- the non-daemon registry ------------------------------------------------

  Only non-daemon threads land here. A daemon thread is deliberately absent:
  the process exit that kills it IS its semantics, and registering one would
  turn `daemon=True` into a join at exit, i.e. into `daemon=False`. }

var
  gLive: array[0..63] of Thread;
  gLiveCount: Integer;
  gLiveLock: TMutex;
  gLiveInit: Boolean;

procedure LiveEnsureInit;
begin
  if gLiveInit then Exit;
  MutexInit(gLiveLock);
  gLiveInit := True;
end;

procedure LiveAdd(t: Thread);
begin
  LiveEnsureInit;
  MutexLock(gLiveLock);
  { A fixed 64 is a cap and not a policy. Overflowing it means a program
    spawned more than 64 NON-DAEMON threads and never joined them, which the
    corpus does not do and which CPython would also make you pay for. The
    thread still RUNS; it simply is not joined at exit, so say so rather than
    dropping it silently. }
  if gLiveCount < 64 then
  begin
    gLive[gLiveCount] := t;
    gLiveCount := gLiveCount + 1;
  end
  else
    WriteLn(StdErr, 'threading: more than 64 unjoined non-daemon threads; ' +
                    'the surplus will not be joined at exit');
  MutexUnlock(gLiveLock);
end;

{ ---- the launcher ----------------------------------------------------------

  Runs ON the spawned thread. `arg` is the Thread instance, exactly as
  palthreadobj's ThreadObjLauncher takes its TThread — the same cast, for the
  same reason: PalThreadCreate's entry takes one opaque Pointer.

  Everything this touches allocates (a Variant call frame, whatever the Python
  body does), which is why --threadsafe is not optional. }
procedure ThreadLauncher(arg: Pointer);
var
  t: Thread;
  n: Int64;
  ignored: Variant;
begin
  t := Thread(arg);
  { The DEC is paired with an INC in Thread.start rather than one here, and the
    asymmetry is deliberate: the parent must be able to see the count go up
    BEFORE it does anything that might block on this thread, and a child that
    has not been scheduled yet has incremented nothing. Counting from the
    parent closes that window; counting from here would leave it open exactly
    when it matters. See pythreadlive.pas. }
  if not pycallback_is(t.FTarget) then
  begin
    PyThreadLiveDec;
    Exit;
  end;
  n := 0;
  { The guard is POSITIVE -- "is this an object?" -- and not the negative
    "is this the Integer default?", which is what it said first and which was
    wrong for a reason worth keeping: a Variant parameter declared `= 0` does
    NOT arrive as an int-tagged 0 when the caller omits it. Measured
    2026-09-10: `pylen_v` on it raised `TypeError: expected a str, list, dict
    or bytes, got NoneType`, so the default fill produces a NONE. Asking what a
    sequence IS survives that; asking what the default is does not, and the
    failure landed on the CHILD thread, several frames from the declaration
    that caused it. A tuple, a list and a string are all tag 7. }
  if pyvar_is_objtag(t.FArgs) then n := pylen_v(t.FArgs);
  if n = 0 then
    ignored := pybound_callv0(t.FTarget)
  else if n = 1 then
    ignored := pybound_callv1(t.FTarget, pyvar_getitem(t.FArgs, 0))
  else if n = 2 then
    ignored := pybound_callv2(t.FTarget,
                              pyvar_getitem(t.FArgs, 0),
                              pyvar_getitem(t.FArgs, 1))
  else if n = 3 then
    ignored := pybound_callv3(t.FTarget,
                              pyvar_getitem(t.FArgs, 0),
                              pyvar_getitem(t.FArgs, 1),
                              pyvar_getitem(t.FArgs, 2))
  else
    { Four or more is a refusal and not a truncation. pybound_callv tops out at
      three, and calling with the wrong arity would either crash or silently
      drop arguments -- both worse than a message naming the limit. }
    WriteLn(StdErr, 'threading: Thread(args=...) supports at most 3 arguments');
  PyThreadLiveDec;
end;

{ ---- Thread ---------------------------------------------------------------- }

constructor Thread.Create(target: Variant = 0; args: Variant = 0;
                          daemon: Boolean = False; name: AnsiString = '');
begin
  { The parameters shadow the fields of the same name, so Self is not optional
    here. Named for the Python kwargs regardless, because that is what binds. }
  Self.FTarget := target;
  Self.FArgs := args;
  Self.daemon := daemon;
  Self.name := name;
  FStarted := False;
  FJoined := False;
  FHandlePtr := nil;
end;

procedure Thread.start;
begin
  { CPython raises RuntimeError on a second start. Raising here keeps the
    mistake visible rather than spawning a second body over one handle, which
    would leak the first thread's stack and make the join ambiguous. }
  if FStarted then
    raise Exception.Create('threading: start() called twice on one Thread');
  if not pycallback_is(FTarget) then
    raise Exception.Create('threading: Thread(target=...) is not callable');
  GetMem(FHandlePtr, SizeOf(TThreadHandle));
  if PalThreadCreate(FHandlePtr^, @ThreadLauncher, Pointer(Self), 0) <> 0 then
  begin
    FreeMem(FHandlePtr);
    FHandlePtr := nil;
    raise Exception.Create('threading: could not start a new thread');
  end;
  FStarted := True;
  PyThreadLiveInc;
  if not daemon then LiveAdd(Self);
end;

function Thread.is_alive: Boolean;
begin
  is_alive := False;
  if (not FStarted) or FJoined or (FHandlePtr = nil) then Exit;
  { TidWord is the kernel's own liveness bit: set at clone time
    (CLONE_PARENT_SETTID), cleared as the thread's last act
    (CLONE_CHILD_CLEARTID). Reading it is the cheapest true answer there is,
    and it needs no bookkeeping of ours to stay correct. }
  is_alive := FHandlePtr^.TidWord <> 0;
end;

function Thread.join(timeout: Double = PY_NO_TIMEOUT): Variant;
var
  t: Integer;
  left, slice: Int64;
begin
  { CPython's join returns None, always -- including on a timeout. The caller
    that cares asks is_alive(). }
  join := pynone;
  if (not FStarted) or FJoined or (FHandlePtr = nil) then Exit;
  if timeout < 0.0 then
  begin
    PalThreadJoin(FHandlePtr^);
    FJoined := True;
    Exit;
  end;
  { A TIMED join, which PalThreadJoin does not offer. Same handshake, waiting
    on the same word, with a deadline: PalFutexWaitTimeout returns early on a
    wake, a timeout, or EAGAIN (the word already moved), so the loop re-reads
    the word every time rather than trusting the return. }
  left := Round(timeout * NS_PER_S);
  while left > 0 do
  begin
    t := FHandlePtr^.TidWord;
    if t = 0 then Break;
    slice := left;
    { Cap a single wait at 50ms so a spurious wake cannot turn a 2-second
      timeout into a 2-second BUSY loop, and so the deadline is re-derived
      often enough to stay honest without a clock syscall per iteration. }
    if slice > 50 * 1000 * 1000 then slice := 50 * 1000 * 1000;
    PalFutexWaitTimeout(@FHandlePtr^.TidWord, t, slice);
    left := left - slice;
  end;
  { Only a thread that actually EXITED may have its stack freed -- freeing the
    stack of a live thread is the one way this can corrupt a running program,
    and a timed-out join is precisely the case where it has not exited. }
  if FHandlePtr^.TidWord = 0 then
  begin
    PalThreadJoin(FHandlePtr^);
    FJoined := True;
  end;
end;

{ ---- Event ----------------------------------------------------------------- }

constructor Event.Create;
begin
  { Manual reset: Python's Event stays signalled until clear() and releases
    EVERY waiter. An auto-reset event would hand the flag to one waiter and
    clear itself, which is a different object (a semaphore of one). }
  EventInit(FEv, True);
end;

procedure Event.set;
begin
  EventSet(FEv);
end;

procedure Event.clear;
begin
  EventReset(FEv);
end;

function Event.is_set: Boolean;
begin
  is_set := FEv.State <> 0;
end;

function Event.wait(timeout: Double = PY_NO_TIMEOUT): Boolean;
var
  left, slice: Int64;
begin
  if FEv.State <> 0 then
  begin
    wait := True;
    Exit;
  end;
  if timeout < 0.0 then
  begin
    EventWait(FEv);
    wait := True;
    Exit;
  end;
  left := Round(timeout * NS_PER_S);
  while (left > 0) and (FEv.State = 0) do
  begin
    slice := left;
    if slice > 50 * 1000 * 1000 then slice := 50 * 1000 * 1000;
    PalFutexWaitTimeout(@FEv.State, 0, slice);
    left := left - slice;
  end;
  { The RETURN is re-read from the word, never inferred from which arm of the
    loop ended it: a wake and a timeout can race, and answering False for an
    event that is now set would make the corpus's `if stop.wait(period): break`
    miss its own shutdown. }
  wait := FEv.State <> 0;
end;

{ ---- Lock ------------------------------------------------------------------ }

constructor Lock.Create;
begin
  MutexInit(FM);
end;

function Lock.acquire(blocking: Boolean = True): Boolean;
begin
  if blocking then
  begin
    MutexLock(FM);
    acquire := True;
  end
  else
    acquire := MutexTryLock(FM);
end;

procedure Lock.release;
begin
  MutexUnlock(FM);
end;

function Lock.locked: Boolean;
begin
  { TryLock is the only honest probe of a futex mutex from outside: reading the
    word would race. Taking it and putting it straight back reports the state
    at the instant it was asked, which is all `locked()` ever promises in
    CPython either. }
  if MutexTryLock(FM) then
  begin
    MutexUnlock(FM);
    locked := False;
  end
  else
    locked := True;
end;

finalization
  { CPython joins every non-daemon thread before the interpreter exits. Without
    this the process teardown (exit_group) kills them mid-flight and whatever
    they were doing is lost with no diagnostic -- a silent wrong answer, which
    is the shape this project ranks worst. Daemon threads are NOT here on
    purpose: being killed at exit is what daemon MEANS. }
  while gLiveCount > 0 do
  begin
    gLiveCount := gLiveCount - 1;
    if gLive[gLiveCount] <> nil then gLive[gLiveCount].join;
  end;
end.

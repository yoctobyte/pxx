{ SPDX-License-Identifier: Zlib }
unit mimic_queue;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `queue` module — a bounded FIFO with a blocking discipline.

  `import queue` RESOLVES here through the NilPy import resolver's `mimic_`
  fallback, so no file in the tree carries the stdlib's name and `--no-shims`
  can turn the substitution into an error. See devdocs/dev/python-compat-tiers.md.

  THE CONTAINER WAS FREE AND THE SEMANTICS WERE THE WHOLE TICKET. `TPyDeque`
  landed in pylib on 2026-09-09 for `collections.deque` and is exactly the right
  storage: O(1) amortised popleft, no shifting. A Queue is that plus a capacity
  bound plus a policy about what happens when you ask for something that is not
  there. None of the storage work needed doing twice.

  ## Why the blocking arms RAISE rather than block, and why that is not the
  ## easy half

  CPython's Queue exists to move objects between THREADS. `get()` waits until an
  item arrives; `put()` on a full bounded queue waits until room appears; the
  `_nowait` variants raise `Empty`/`Full` instead of waiting. lekkerzeilen uses
  both halves — `get_nowait()` in the render loop under `except queue.Empty`
  (gauges.py:443, app.py:1345) and a genuinely blocking `get()` in a loader
  thread (app.py:1294), with `_ready` bounded at maxsize=2 so its `put` blocks
  too.

  Measured 2026-09-10: **NilPy has no `threading`** — `import threading` reaches
  no unit and no shim — so today there is no second thread that could ever
  satisfy a wait. In that world:

    * a blocking `get()` on a NON-EMPTY queue is satisfiable immediately, and we
      answer exactly as CPython does. This is the common case and it is not a
      subset of anything.
    * a blocking `get()` on an EMPTY queue would, in CPython, hang forever —
      because nothing can ever put. That is a deadlock in CPython too, not a
      behaviour any program depends on. Raising here turns an unobservable hang
      into a diagnosis, and the mistake stays visible, which is what CLAUDE.md
      asks for where an input is only produced by an error.

  So this is NOT "implement the non-blocking half and hope". It is: implement
  every arm that has a defined answer, and refuse — loudly, naming the reason —
  the one arm whose only CPython behaviour is to hang.

  ## mimic_threading LANDED, AND BOTH THINGS CHANGED IN THE SAME COMMIT

  Both are done, 2026-09-10, and neither was safe alone:

    1. `WouldBlock` IS the wait now. `get()` on an empty queue and `put()` on a
       full one sleep on a condition variable until another thread satisfies
       them, which is what CPython does and what the corpus's loader thread
       needs (`_ready` is maxsize=2, so its put really does block while the
       render loop drains with get_nowait).
    2. **The class has a lock.** There was none, deliberately, because with one
       thread a lock is pure cost and an uncontended lock is an untested one.
       A Queue reachable from two threads without a mutex is a data race in the
       one class whose entire purpose is cross-thread hand-off.

  ## The DIAGNOSIS the old refusal carried is not lost, and that is on purpose

  The refusal this replaces was not merely a placeholder -- it turned an
  unobservable hang into a message. Blocking correctly would have thrown that
  away for every SINGLE-THREADED program, which is most of them: `q.get()` on
  an empty queue with no other thread is a guaranteed deadlock, and CPython's
  answer to it is to hang forever.

  So the wait asks first whether anything could ever satisfy it.
  `pythreadlive.PyThreadLiveAny` answers "is at least one spawned thread
  alive"; when it is False the old refusal is raised, word for word, because
  the situation it describes is exactly the situation. When it is True the call
  blocks, because now something can arrive.

  That is strictly better than CPython on a program that is already wrong, and
  identical to CPython on every program that is not -- which is the direction
  the upward-compatibility rule points. `pythreadlive` is a unit of its own so
  that `import queue` does not drag `palthread` (and therefore --threadsafe)
  into a single-threaded program; its header has the full argument. }

interface

uses pylib, sysutils, palsync, pythreadlive;

const
  { See the note on put/get: a parameter default must be a constant expression
    and a bare negative float literal is not accepted as one in this dialect. }
  PY_QUEUE_NO_TIMEOUT = -1.0;

type
  { queue.Empty and queue.Full. Distinct classes because real code catches them
    BY NAME as control flow -- `except queue.Empty:` is how both corpus call
    sites drive their render loop -- so a shared base or a bare Exception would
    turn a normal empty poll into a caught-everything handler. }
  Empty = class(Exception);
  Full = class(Exception);

  { The class is `Queue`, spelled as CPython spells it. No reserved-word
    collision here, unlike mimic_array's `array_` -- `queue` is not a Pascal
    keyword, and neither is `Queue`. }
  Queue = class
  public
    FBuf: TPyDeque;
    { The mutex and the two condition variables live IN the object, so their
      addresses are stable for its life -- palsync asks exactly that. Two
      condvars and not one: a `get` waiter and a `put` waiter are waiting for
      opposite events, and signalling one predicate wakes the other's sleepers
      for nothing. With maxsize=2 and a full queue that is the common case. }
    FLock: TMutex;
    FNotEmpty: TCondVar;
    FNotFull: TCondVar;
    { 0 means unbounded, which is CPython's own encoding: Queue(maxsize=0) and
      Queue() are the same queue. Named `maxsize` and public because CPython
      exposes it as an attribute and code reads it. }
    maxsize: Integer;
    { ONE constructor with a DEFAULT, not two overloads. See the note in the
      implementation: a keyword argument does not bind on an OVERLOADED Pascal
      constructor. REVERT TO TWO OVERLOADS when that is fixed.
      The parameter is named `maxsize` and not `n` because `Queue(maxsize=2)`
      is how app.py:575 writes it, and a keyword argument binds by the PASCAL
      parameter's name. With `n` it did not bind at all and the compiler
      correctly refused: "Queue() is missing a value for parameter 1". It
      shadows the field of the same name inside the body, hence Self. }
    constructor Create(maxsize: Integer = 0);
    { Internals, public only because this dialect's `private` and the shim
      resolver have not been checked to agree; nothing Python-facing should
      call them. The two predicates exist so the public accessors and the
      blocking loops read ONE spelling of "is it full" -- a second copy is a
      second chance for the wait and the check to disagree, and the copy that
      goes wrong is the one inside the loop, where it reads as a lost wakeup
      rather than as a typo. }
    function IsEmpty_locked: Boolean;
    function IsFull_locked: Boolean;
    function WaitOn(var c: TCondVar; const what: AnsiString;
                    var leftNs: Int64; bounded: Boolean): Boolean;
    function qsize: Integer;
    function empty: Boolean;
    function full: Boolean;
    { `block` and `timeout` are CPython's own signature and cost nothing here:
      put_nowait/get_nowait are literally these with block=False, which is how
      CPython defines them too. timeout < 0 means "no timeout", spelled as a
      named constant because a Pascal parameter default must be a constant
      expression and a bare -1.0 is not accepted as one. }
    function put(const v: Variant; block: Boolean = True;
                 timeout: Double = PY_QUEUE_NO_TIMEOUT): Variant;
    function put_nowait(const v: Variant): Variant;
    function get(block: Boolean = True;
                 timeout: Double = PY_QUEUE_NO_TIMEOUT): Variant;
    function get_nowait: Variant;
    { `len(q)` is NOT a Python Queue operation -- CPython's Queue defines no
      __len__ and `len(q)` raises TypeError. It is here anyway because without
      it a `while q:` on this class is decided by the overload matcher reading a
      length off unrelated bytes rather than refused
      (bug-nilpy-dunder-protocols-ignored-fall-back-to-handle-arithmetic), and a
      wrong answer is worse than an accepted extra. Accepting what CPython
      rejects is the upward-compatible direction. }
    function __len__: Integer;
  end;

implementation

const
  NS_PER_S = 1000 * 1000 * 1000;

constructor Queue.Create(maxsize: Integer);
begin
  FBuf := TPyDeque.Create;
  MutexInit(FLock);
  CondInit(FNotEmpty);
  CondInit(FNotFull);
  { CPython treats any maxsize <= 0 as unbounded, not just 0. }
  if maxsize < 0 then Self.maxsize := 0 else Self.maxsize := maxsize;
end;

{ ---- the unlocked predicates -----------------------------------------------

  Named `_locked` because the CALLER must hold FLock. Split out so the public
  accessors and the blocking loops read the same two conditions -- a second
  spelling of "is it full" is a second chance for the wait and the check to
  disagree, and the one that goes wrong is the one inside the loop, where it
  reads as a lost wakeup rather than as a typo. }

function Queue.IsEmpty_locked: Boolean;
begin
  IsEmpty_locked := FBuf.__len__ = 0;
end;

function Queue.IsFull_locked: Boolean;
begin
  IsFull_locked := (maxsize > 0) and (FBuf.__len__ >= maxsize);
end;

function Queue.qsize: Integer;
begin
  MutexLock(FLock);
  qsize := FBuf.__len__;
  MutexUnlock(FLock);
end;

function Queue.__len__: Integer;
begin
  MutexLock(FLock);
  __len__ := FBuf.__len__;
  MutexUnlock(FLock);
end;

function Queue.empty: Boolean;
begin
  MutexLock(FLock);
  empty := IsEmpty_locked;
  MutexUnlock(FLock);
end;

function Queue.full: Boolean;
begin
  MutexLock(FLock);
  full := IsFull_locked;
  MutexUnlock(FLock);
end;

{ The one place that knows what "would have waited with nobody to satisfy it"
  means. Called from both blocking arms so the message and the policy exist
  once. Its TEXT is the refusal this file carried before threading landed, kept
  word for word because the situation it describes has not changed -- only the
  test for it has: it used to be "NilPy has no threading", it is now "no thread
  is alive right now". }
procedure DeadWait(const what: AnsiString);
begin
  raise Exception.Create(
    'queue.Queue.' + what + '() would block forever: no other thread is alive, '
    + 'so nothing can satisfy this wait. In CPython this call hangs rather than '
    + 'returning, so nothing is being refused that a working program relies on. '
    + 'Use ' + what + '_nowait() and catch queue.Empty/queue.Full, which is what '
    + 'a single-threaded poll wants -- or start the thread that was meant to '
    + 'feed this queue.');
end;

{ Sleep on `c` until the predicate might have changed, or refuse. Call with
  FLock HELD; it is dropped and re-taken by CondWait, which is the entire
  reason the predicate loops in the callers rather than being tested once.

  Returns False when a bounded wait ran out. }
function Queue.WaitOn(var c: TCondVar; const what: AnsiString;
                      var leftNs: Int64; bounded: Boolean): Boolean;
var
  slice: Int64;
begin
  WaitOn := True;
  { THE DEADLOCK TEST, and it is asked HERE rather than once before the loop:
    a thread can exit while this one sleeps, so a queue that had a feeder when
    the wait began can lose it. Asking each time around turns that from an
    unobservable hang into the same diagnosis.

    The lock is DROPPED before the raise. An exception thrown with FLock held
    unwinds straight past every MutexUnlock below it, and the next caller of
    this queue -- including a handler that catches the very exception being
    raised -- then blocks forever on a mutex nobody will release. That is a
    deadlock introduced by the code whose job is to diagnose one. }
  if not PyThreadLiveAny then
  begin
    MutexUnlock(FLock);
    DeadWait(what);
  end;
  if not bounded then
  begin
    CondWait(c, FLock);
    Exit;
  end;
  slice := leftNs;
  { Cap one sleep so the deadlock test above is re-asked at a bounded rate even
    inside a long timeout -- a thread that dies one second into a ten-second
    wait should not cost the other nine. }
  if slice > 50 * 1000 * 1000 then slice := 50 * 1000 * 1000;
  CondWaitTimeout(c, FLock, slice);
  leftNs := leftNs - slice;
  WaitOn := leftNs > 0;
end;

function Queue.put(const v: Variant; block: Boolean = True;
                   timeout: Double = PY_QUEUE_NO_TIMEOUT): Variant;
var
  leftNs: Int64;
  bounded, more: Boolean;
begin
  MutexLock(FLock);
  bounded := block and (timeout >= 0.0);
  leftNs := 0;
  if bounded then leftNs := Round(timeout * NS_PER_S);
  more := True;
  while IsFull_locked and more do
  begin
    if not block then
    begin
      MutexUnlock(FLock);
      raise Full.Create('put_nowait on a full queue (maxsize '
                        + IntToStr(maxsize) + ')');
    end;
    more := WaitOn(FNotFull, 'put', leftNs, bounded);
  end;
  if IsFull_locked then
  begin
    MutexUnlock(FLock);
    raise Full.Create('put timed out on a full queue (maxsize '
                      + IntToStr(maxsize) + ')');
  end;
  put := FBuf.append(v);
  { Signal INSIDE the lock. Signalling outside is the classic optimisation and
    it is wrong here for a reason that only bites under contention: between the
    unlock and the signal another thread can take the lock, find the queue
    non-empty, and drain it -- and then the signal wakes a waiter for an item
    that is already gone, which its predicate loop handles, but the waiter that
    was going to be woken NEXT never is. palsync's condvar bumps a sequence
    counter, so signalling under the lock has no lost-wakeup cost. }
  CondSignal(FNotEmpty);
  MutexUnlock(FLock);
end;

function Queue.put_nowait(const v: Variant): Variant;
begin
  put_nowait := put(v, False);
end;

function Queue.get(block: Boolean = True;
                   timeout: Double = PY_QUEUE_NO_TIMEOUT): Variant;
var
  leftNs: Int64;
  bounded, more: Boolean;
begin
  MutexLock(FLock);
  bounded := block and (timeout >= 0.0);
  leftNs := 0;
  if bounded then leftNs := Round(timeout * NS_PER_S);
  more := True;
  while IsEmpty_locked and more do
  begin
    if not block then
    begin
      MutexUnlock(FLock);
      { CPython raises queue.Empty with no message here, and the message is the
        whole reason this is not a bare Exception: `except queue.Empty` in the
        render loop must catch THIS and not, say, a KeyError from the work the
        handler was about to do. }
      raise Empty.Create('get_nowait on an empty queue');
    end;
    more := WaitOn(FNotEmpty, 'get', leftNs, bounded);
  end;
  if IsEmpty_locked then
  begin
    MutexUnlock(FLock);
    raise Empty.Create('get timed out on an empty queue');
  end;
  get := FBuf.popleft;
  CondSignal(FNotFull);
  MutexUnlock(FLock);
end;

function Queue.get_nowait: Variant;
begin
  get_nowait := get(False);
end;

end.

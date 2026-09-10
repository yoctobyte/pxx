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

  ## WHEN mimic_threading LANDS, TWO THINGS HERE MUST CHANGE TOGETHER

  pxx already has real threads at the RTL level (`lib/rtl/palthread.pas`:
  PalThreadCreate/Join/Self/Exit, clone-based), so `threading` is a reachable
  ticket rather than a wish, and these arms will stop being hypothetical:

    1. `WouldBlock` below becomes a real wait, in the two places it is called.
    2. **THIS CLASS IS NOT THREAD-SAFE AND MUST BECOME SO IN THE SAME CHANGE.**
       There is no lock here, because with one thread a lock is pure cost and a
       lock that is never contended is also never tested. A Queue whose whole
       purpose is cross-thread hand-off, made reachable from two threads without
       a mutex, is a data race in the one class most likely to be used across
       threads. Neither change is safe alone.

  Recorded here rather than only in the ticket because this file is what someone
  writing mimic_threading will open. }

interface

uses pylib, sysutils;

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
    function qsize: Integer;
    function empty: Boolean;
    function full: Boolean;
    function put(const v: Variant): Variant; overload;
    function put_nowait(const v: Variant): Variant;
    function get: Variant;
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

constructor Queue.Create(maxsize: Integer);
begin
  FBuf := TPyDeque.Create;
  { CPython treats any maxsize <= 0 as unbounded, not just 0. }
  if maxsize < 0 then Self.maxsize := 0 else Self.maxsize := maxsize;
end;

function Queue.qsize: Integer;
begin
  qsize := FBuf.__len__;
end;

function Queue.__len__: Integer;
begin
  __len__ := FBuf.__len__;
end;

function Queue.empty: Boolean;
begin
  empty := FBuf.__len__ = 0;
end;

function Queue.full: Boolean;
begin
  full := (maxsize > 0) and (FBuf.__len__ >= maxsize);
end;

{ The one place that knows what "would have waited" means today. Called from
  both blocking arms so the message and the policy exist once -- when
  mimic_threading lands this becomes the wait, and there is exactly one site to
  change rather than two that must be found. }
procedure WouldBlock(const what: AnsiString);
begin
  raise Exception.Create(
    'queue.Queue.' + what + '() would block forever: NilPy has no threading '
    + 'yet, so no other thread can satisfy this wait. In CPython this call '
    + 'hangs rather than returning, so nothing is being refused that a working '
    + 'single-threaded program relies on. Use ' + what + '_nowait() and catch '
    + 'queue.Empty/queue.Full, which is what a single-threaded poll wants.');
end;

function Queue.put(const v: Variant): Variant;
begin
  { Satisfiable: answer exactly as CPython does. The bound is checked FIRST so
    an unbounded queue -- every Queue() in the corpus but one -- never reaches
    the refusal at all. }
  if not full then
  begin
    put := FBuf.append(v);
    Exit;
  end;
  WouldBlock('put');
end;

function Queue.put_nowait(const v: Variant): Variant;
begin
  if full then
    raise Full.Create('put_nowait on a full queue (maxsize '
                      + IntToStr(maxsize) + ')');
  put_nowait := FBuf.append(v);
end;

function Queue.get: Variant;
begin
  if FBuf.__len__ > 0 then
  begin
    get := FBuf.popleft;
    Exit;
  end;
  WouldBlock('get');
end;

function Queue.get_nowait: Variant;
begin
  { CPython raises queue.Empty with no message here, and the message is the
    whole reason this is not a bare Exception: `except queue.Empty` in the
    render loop must catch THIS and not, say, a KeyError from the work the
    handler was about to do. }
  if FBuf.__len__ = 0 then raise Empty.Create('get_nowait on an empty queue');
  get_nowait := FBuf.popleft;
end;

end.

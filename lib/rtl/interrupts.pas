{ SPDX-License-Identifier: Zlib }
unit interrupts;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Interrupt events reach application code OUTSIDE interrupt context, by
  construction (feature-s-interrupt-events-reach-python-outside-interrupt-context;
  design settled by the owner 2026-09-22).

  THE ONE INVARIANT, AND IT IS STRUCTURAL RATHER THAN A RULE TO FOLLOW. No
  application callback registered here is ever reachable from trap context. The
  producer side (IntPush) is the ONLY thing an ISR calls; it takes no callback,
  never allocates, never blocks and never dispatches. Callbacks run only from
  IntPoll, which an ISR has no way to reach. So "do not run Python in an
  interrupt" is not a discipline anyone has to maintain -- there is no path.

  This extends the seam lib/rtl/platform/esp/esptimer.pas already established
  (the library owns the handler; the user supplies a plain callback and never
  sees esp_intr_alloc or `iram;`). It does not invent a convention.

  WHAT IS HERE AND WHAT IS NOT. This is the PUMP half: the queue, the drain at
  the blocking points the RTL already owns, the re-entrancy refusal, the
  per-drain budget, the ring-full policy and the iterator. The GPIO edge SOURCE
  lives in lib/rtl/platform/esp/espgpio.pas (on_rising / on_falling /
  on_change), whose ISR calls IntPush and nothing else; it was measured on an
  ESP32-S3 board on 2026-09-24 (examples/esp32/gpio-edge-s3), because qemu
  models no GPIO input path at all. Everything in THIS unit is also exercised
  on x86-64 against a synthetic source, which needs no board.

  THE PUMP IS INSTALLED, NOT LINKED IN -- AND THAT IS A CLAIM ABOUT THE HOOK,
  NOT ABOUT THIS UNIT'S OWN SIZE. `platform.PalPendingDrain` is a nil procedure
  variable that the RTL's blocking points call when it is set; this unit assigns
  it when the FIRST handler is registered. A program that never registers one
  keeps a nil pointer and its behaviour exactly. That is deliberate: making
  mimic_time `uses interrupts` would root the queue in every program that
  imports `time`, which on ESP is a real cost paid by programs that never asked
  for it.

  WHAT IT DOES *NOT* MEAN, MEASURED 2026-09-24 AT 584644986 BECAUSE THE SENTENCE
  ABOVE READS AS IF IT DID: `uses interrupts` now costs ~300 KB of code, because
  the Python surface below names pylib and PYLIB CANNOT BE DROPPED BY DCE. One
  Pascal program registering one handler and never mentioning Python:

      target            without the Python surface   with it
      x86-64                     23,097 B          320,881 B
      esp32c3 --platform=posix   62,028 B          765,604 B
      xtensa  --platform=posix   52,496 B          671,044 B  (*)

      (*) crosses the 512 KiB CALL0/CALL8 forward-call reach, so xtensa needs
          --xtensa-long-calls, which other lib/rtl cross rows already pass.

  The cost is pylib's and not this unit's: a bare `uses pylib` program measures
  316,004 B, and moving pylib to the implementation section changes nothing
  (316,023 B with the only pylib-using routine unreachable). So there is no
  arrangement of this file that is cheaper.

  IT IS PAID ANYWAY AND A SPLIT WOULD NOT HELP. `import X` binds unit `X` first
  and falls back to `mimic_X` only on a miss (pasparser_proc.inc:6851), so an
  `interrupts.pas` without the Python surface would still win the import and
  hand NilPy the Pascal spellings -- IntPush, TIntEvent, a procedure-type
  callback it cannot supply. One unit is the only structure that resolves. A
  NilPy program links pylib regardless, so the Python surface costs the intended
  consumer nothing; the payer is a PASCAL program that uses this unit, and the
  bare ESP profile -- the SRAM-constrained one -- does not consume lib/rtl at all
  (no bare Makefile row passes -Fulib/rtl). Revisit if a Pascal ESP program ever
  needs the pump under a flash budget this does not fit.

  NOT BUILT HERE, DELIBERATELY: the owner's "hidden loop" for a script that
  registers handlers and then falls off the end. It needs two things settled
  that this unit does not settle -- it must engage only when a handler is
  registered, and a desktop program must still EXIT -- and getting the second
  wrong hangs every NilPy script that imports this unit at exit on the host,
  which is a regression in ordinary frontend use rather than in an ESP feature.
  The ticket says not to land it in the same commit as the pump. }

interface

uses pylib;   { Variant, TPyList -- the Python surface below is part of the
                interface, so the types it names have to be visible here }

const
  { Source tags. A bare pin number cannot distinguish two sources on one pin
    and cannot express a non-GPIO source at all, so an event carries
    (source, id) and not just an id. }
  INT_SRC_NONE  = 0;
  INT_SRC_GPIO  = 1;
  INT_SRC_TIMER = 2;
  INT_SRC_USER  = 3;
  { The synthetic source the host tests push from. Named rather than borrowing
    INT_SRC_GPIO so a test can never be mistaken for evidence about real edge
    delivery, which only a board can give (examples/esp32/gpio-edge-s3). }
  INT_SRC_TEST  = 99;

  INT_RING_CAPACITY = 64;
  INT_DEFAULT_DRAIN_BUDGET = 16;

type
  TIntEvent = record
    Source: Integer;   { INT_SRC_* }
    Id:     Integer;   { pin, channel, or whatever the source numbers by }
    StampMs: Int64;    { monotonic milliseconds at PUSH time, not at delivery }
    Seq:    Int64;     { push ordinal, 1-based and never reused }
  end;

  TIntCallback = procedure(const ev: TIntEvent);

{ ---- producer: the only thing an ISR calls ------------------------------- }

{ Push an event. Returns False when the ring is full, in which case the event
  is DROPPED and IntDropped increases. Never blocks, never allocates, never
  dispatches a callback. }
function IntPush(source, id: Integer): Boolean;

{ ---- registration -------------------------------------------------------- }

{ Register cb for one source. Passing nil unregisters. The first registration
  installs the RTL drain hook; the last unregistration removes it. }
procedure IntOnEvent(source: Integer; cb: TIntCallback);
function  IntHandlerCount: Integer;

{ ---- drain --------------------------------------------------------------- }

{ Deliver up to the budget. Returns how many were delivered. Returns 0
  immediately if a drain is already in progress on this call stack. }
function IntPoll: Integer;

function  IntPending: Integer;
function  IntDropped: Int64;
function  IntDelivered: Int64;
function  IntInDrain: Boolean;
procedure IntSetDrainBudget(n: Integer);
function  IntDrainBudget: Integer;

{ Take one event without running callbacks -- the Pascal half of iterating
  `for ev in interrupts.events()`. False when the queue is empty. }
function IntNext(var ev: TIntEvent): Boolean;

{ Drop every queued event and reset the counters. For tests and for a program
  that wants a clean slate after reconfiguring its sources. }
procedure IntReset;

{ ---- the Python module surface ------------------------------------------- }

{ `import interrupts` resolves to THIS unit -- the unit name IS the module name,
  which is the established convention (lib/rtl/base64.pas is the worked example
  and devdocs/dev/pxx-crash-course.md states the rule).

  THAT CONVENTION IS AN ALLOWLIST IN THE COMPILER AND NOT AN AUTOMATIC RULE,
  which this unit had to learn the expensive way: a bare NilPy import of a
  Pascal unit is REFUSED ("is the Pascal unit ..., not a Python module") unless
  the name appears in PyRtlUnitServesPython (pasparser_proc.inc). `interrupts`
  was added there in the same commit as this surface, on that function's own
  stated criterion -- a unit earns the entry by having a Python surface NilPy
  can SPEAK, which is exactly why png and image are deliberately absent from it.
  So this DOES touch the import mechanism, by one line, and a reader who assumes
  "the unit name is the module name" holds without it will find the import
  refused.

  THE SPELLINGS ARE BORROWED AND THE ARCHITECTURE IS NOT. The owner's ruling,
  2026-09-22: "don't re-invent wheels, use existing naming where possible" AND
  "no, we will _not_ do what micropython does. that is their approach and it's
  fair, but we are a compiler." So there is no `machine.Pin` and no
  `Pin.irq(handler=...)` here, deliberately. The reason is not taste: MicroPython
  is an interpreter, so a pending-work check between bytecodes is free and
  "no allocation in a handler" is a mode bit. We emit native code, where the same
  check has to be EMITTED -- which is why the drain sits at blocking points we
  already own rather than everywhere. A `machine`-shaped surface is separate work
  that nobody has ranked, and it must not arrive as a side effect of this.

  A PYTHON CALLABLE REGISTERED HERE CANNOT RUN IN INTERRUPT CONTEXT. That is
  structural and not a warning to heed: `on_event` stores the callable, and the
  only thing that invokes it is `poll`, reached from ordinary control flow. The
  producer side is IntPush, which holds no callable and dispatches nothing. There
  is no path from a trap to this table. }

type
  { What `for ev in interrupts.events()` yields.

    A CLASS WITH NAMED FIELDS rather than a tuple, following
    lib/rtl/mimic_shutil.pas's terminal_size and for its reason: a TPyList would
    give indexing while losing the names, and the names are the half that code
    actually reads. `ev.source` and `ev.id` are the spellings; `ev[0]` is not
    supported and no caller wants it. }
  event = class
  public
    source: Integer;
    id:     Integer;
    seq:    Int64;
    ms:     Int64;
    constructor Create(const e: TIntEvent);
  end;

{ Drain and RETURN the events, without running callbacks. The iteration half of
  the surface: `for ev in interrupts.events():`. Returns an empty list when
  nothing is queued -- never None, so the `for` is always well formed. }
function events: TPyList;

{ Drain and RUN the registered callbacks. Returns how many were delivered.
  This is the explicit pump for a program that wants to service work without
  blocking; the RTL's blocking points call the same drain by themselves. }
function poll: Integer;

function pending: Integer;
function dropped: Int64;
function delivered: Int64;

{ Register a PYTHON callable for one source. Pass None to unregister.
  The callable is invoked with one argument, an `event`. }
procedure on_event(source: Integer; const cb: Variant);

{ Push an event as a source would. This is the SYNTHETIC source: it is what a
  host test uses in place of an edge nobody can generate here, and it is also
  the entry point a user's own Pascal or C handler calls. It is deliberately NOT
  named for GPIO: GPIO edges come from espgpio's armed pins, and a synthetic
  push must not be mistakable for one. }
function push(source, id: Integer): Boolean;

implementation

uses platform,    { PalPendingDrain -- the blocking-point hook }
     palatomic;  { RingCount is shared with an ISR -- see the ring's comment }

type
  THandlerSlot = record
    Source: Integer;
    Cb:     TIntCallback;   { a Pascal handler }
    { ...or a Python one. ONE TABLE AND ONE DISPATCH POINT for both, rather than
      a second registry beside the first: two mechanisms serving one concept is
      the smell CLAUDE.md names, and it would give source->handler two answers
      that could disagree. pycallback_is() is what makes a slot's Python half
      live, so an unset Variant is simply not a handler. }
    PyCb:   Variant;
  end;

const
  MAX_HANDLERS = 8;

var
  Ring:      array[0 .. INT_RING_CAPACITY - 1] of TIntEvent;
  { A SINGLE-PRODUCER / SINGLE-CONSUMER RING THAT AN INTERRUPT CAN PRE-EMPT
    AT ANY INSTRUCTION. The producer is an ISR (espgpio's edge handler) and the
    consumer is ordinary code, on the same core, so every line of IntNext can
    be interrupted by an IntPush. Two rules make that safe:
      - each index has ONE writer: RingTail only IntPush writes, RingHead only
        IntNext writes. The slot a push fills never depends on the consumer's
        index, so a push landing between IntNext's head advance and its count
        decrement fills the right slot. Deriving it as Head+Count, as this did
        first, puts that push one slot past the tail and leaves a hole the
        consumer later reads as a stale event.
      - RingCount is the only word both sides WRITE, and it moves by an atomic
        add. `RingCount := RingCount - 1` is load/subtract/store, and a push
        between the load and the store is lost from the count: an edge counted
        as neither delivered nor dropped, which is the COUNT acceptance
        (pushed == delivered + dropped) failing without a sound.
    The consumer decrements AFTER copying its slot out, so a stale-high count
    seen by a push can only make it drop conservatively, never overwrite.
    NOT covered: two producers pre-empting each other (a task-side `push`
    interrupted by an ISR push). That is two writers of RingTail; the
    synthetic source is for host tests, where no ISR exists. }
  RingHead:  Integer;   { next slot to read; the consumer's }
  RingTail:  Integer;   { next slot to fill; the producer's }
  RingCount: LongInt;   { how many are queued; atomic, see above }
  Handlers:  array[0 .. MAX_HANDLERS - 1] of THandlerSlot;
  NHandlers: Integer;
  Dropped:   Int64;
  Delivered: Int64;
  PushSeq:   Int64;
  Budget:    Integer;
  InDrain:   Boolean;
  BudgetSet: Boolean;

function CurrentBudget: Integer;
begin
  if not BudgetSet then
    Result := INT_DEFAULT_DRAIN_BUDGET
  else
    Result := Budget;
end;

function IntPush(source, id: Integer): Boolean;
var slot: Integer;
begin
  { RING-FULL POLICY: DROP THE NEWEST AND COUNT IT. Chosen, not defaulted.
    The alternative is to overwrite the oldest, which keeps the queue fresh and
    silently rewrites history a consumer has not seen yet -- so a program that
    was late would observe a gap in Seq with no record of where. Dropping the
    newest loses the same number of events and leaves every delivered one
    contiguous, which is what makes the count checkable at all.

    EITHER WAY THE COUNT MUST BE OBSERVABLE, and that is the part that is not
    negotiable: a silently dropped edge is exactly the plausible-wrong-value
    failure this repo keeps paying for. IntDropped is the record. }
  if RingCount >= INT_RING_CAPACITY then
  begin
    Dropped := Dropped + 1;
    Result := False;
    Exit;
  end;
  PushSeq := PushSeq + 1;
  slot := RingTail;
  RingTail := (RingTail + 1) mod INT_RING_CAPACITY;
  Ring[slot].Source := source;
  Ring[slot].Id     := id;
  Ring[slot].Seq    := PushSeq;
  { Timestamp at PUSH, so a late drain does not misreport when the thing
    happened. A monotonic read is the honest clock for an interval; wall time
    can step. MILLISECONDS because that is the resolution the PAL actually
    offers -- PalMonotonicMillis is the only monotonic source in platform.pas,
    and there is no nanosecond variant to call. Named StampMs rather than Stamp
    so nobody reads a unit into it that the PAL cannot deliver. }
  Ring[slot].StampMs := PalMonotonicMillis;
  { Publish LAST, after the slot is filled: the consumer reads a slot only
    once the count says it exists. }
  InterLockedIncrement(RingCount);
  Result := True;
end;

function IntNext(var ev: TIntEvent): Boolean;
begin
  if RingCount <= 0 then
  begin
    Result := False;
    Exit;
  end;
  ev := Ring[RingHead];
  RingHead := (RingHead + 1) mod INT_RING_CAPACITY;
  InterLockedDecrement(RingCount);
  Result := True;
end;

function FindHandler(source: Integer): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to NHandlers - 1 do
    if Handlers[i].Source = source then
    begin
      Result := i;
      Exit;
    end;
end;

{ The RTL blocking points call THIS through platform.PalPendingDrain. It is a
  plain procedure with no result, because the hook's callers do not care how
  much was delivered and must not be given a reason to branch on it. }
procedure DrainHook;
begin
  IntPoll;
end;

procedure InstallHook;
begin
  if NHandlers > 0 then
    PalPendingDrain := @DrainHook
  else
    PalPendingDrain := nil;
end;

{ A slot is live while EITHER half is set, so unregistering one does not take
  the other's registration with it. }
function SlotIsLive(idx: Integer): Boolean;
begin
  Result := (Handlers[idx].Cb <> nil) or pycallback_is(Handlers[idx].PyCb);
end;

procedure DropSlot(idx: Integer);
begin
  while idx < NHandlers - 1 do
  begin
    Handlers[idx] := Handlers[idx + 1];
    idx := idx + 1;
  end;
  NHandlers := NHandlers - 1;
end;

function EnsureSlot(source: Integer): Integer;
begin
  Result := FindHandler(source);
  if Result >= 0 then Exit;
  if NHandlers >= MAX_HANDLERS then
  begin
    Result := -1;
    Exit;
  end;
  Handlers[NHandlers].Source := source;
  Handlers[NHandlers].Cb := nil;
  Handlers[NHandlers].PyCb := pynone;
  Result := NHandlers;
  NHandlers := NHandlers + 1;
end;

procedure IntOnEvent(source: Integer; cb: TIntCallback);
var idx: Integer;
begin
  idx := FindHandler(source);
  if cb = nil then
  begin
    { unregister the PASCAL half only; drop the slot when nothing is left }
    if idx >= 0 then
    begin
      Handlers[idx].Cb := nil;
      if not SlotIsLive(idx) then DropSlot(idx);
    end;
    InstallHook;
    Exit;
  end;
  idx := EnsureSlot(source);
  if idx < 0 then Exit;
  Handlers[idx].Cb := cb;
  InstallHook;
end;

function IntHandlerCount: Integer;
begin
  Result := NHandlers;
end;

function IntPoll: Integer;
var ev: TIntEvent;
    idx, n, lim: Integer;
    pcb: TIntCallback;
begin
  Result := 0;
  { REFUSE A RE-ENTRANT DRAIN. A callback that calls time.sleep would otherwise
    re-enter the drain from inside itself, and the queue would be consumed by a
    nested call whose caller then reports having delivered events it never saw.
    Returning 0 rather than recursing keeps every event delivered exactly once
    and keeps the outer loop's count true. }
  if InDrain then
    Exit;
  InDrain := True;
  n := 0;
  lim := CurrentBudget;
  { BOUND THE WORK PER DRAIN, so a fast source cannot starve the code that was
    trying to sleep. What is left stays queued and the next blocking point
    takes it -- the events are not lost, only deferred. }
  while (n < lim) and IntNext(ev) do
  begin
    idx := FindHandler(ev.Source);
    if idx >= 0 then
    begin
      { THROUGH A LOCAL, because a procedure variable held in a RECORD FIELD is
        not callable in place here -- `Handlers[idx].Cb(ev)` parses as an
        assignment target and asks for `:=`. The copy is the spelling, not a
        workaround for a bug: the field is read once and called once. }
      pcb := Handlers[idx].Cb;
      if pcb <> nil then
        pcb(ev);
      { The Python half of the SAME slot. Invoked here, on ordinary control
        flow, which is the whole design -- see the unit header. }
      if pycallback_is(Handlers[idx].PyCb) then
        pycallback_call1(Handlers[idx].PyCb, event.Create(ev));
    end;
    Delivered := Delivered + 1;
    n := n + 1;
  end;
  InDrain := False;
  Result := n;
end;

function IntPending: Integer;
begin
  Result := RingCount;
end;

function IntDropped: Int64;
begin
  Result := Dropped;
end;

function IntDelivered: Int64;
begin
  Result := Delivered;
end;

function IntInDrain: Boolean;
begin
  Result := InDrain;
end;

procedure IntSetDrainBudget(n: Integer);
begin
  if n < 1 then
    n := 1;
  Budget := n;
  BudgetSet := True;
end;

function IntDrainBudget: Integer;
begin
  Result := CurrentBudget;
end;

procedure IntReset;
var i: Integer;
begin
  RingHead := 0;
  RingTail := 0;
  RingCount := 0;
  Dropped := 0;
  Delivered := 0;
  PushSeq := 0;
  InDrain := False;
  for i := 0 to MAX_HANDLERS - 1 do
  begin
    Handlers[i].Source := INT_SRC_NONE;
    Handlers[i].Cb := nil;
    Handlers[i].PyCb := pynone;
  end;
  NHandlers := 0;
  InstallHook;
end;

{ ---- the Python module surface ------------------------------------------- }

constructor event.Create(const e: TIntEvent);
begin
  source := e.Source;
  id     := e.Id;
  seq    := e.Seq;
  ms     := e.StampMs;
end;

function events: TPyList;
var ev: TIntEvent;
    n, lim: Integer;
begin
  Result := TPyList.Create;
  { Bounded by the same budget as the callback drain, for the same reason: a
    fast source must not be able to hand back an unbounded list to a program
    that asked for "the events". What is left stays queued. }
  n := 0;
  lim := CurrentBudget;
  while (n < lim) and IntNext(ev) do
  begin
    Result.append_self(event.Create(ev));
    Delivered := Delivered + 1;
    n := n + 1;
  end;
end;

function poll: Integer;
begin
  Result := IntPoll;
end;

function pending: Integer;
begin
  Result := IntPending;
end;

function dropped: Int64;
begin
  Result := IntDropped;
end;

function delivered: Int64;
begin
  Result := IntDelivered;
end;

procedure on_event(source: Integer; const cb: Variant);
var idx: Integer;
begin
  if not pycallback_is(cb) then
  begin
    { None (or anything not callable) unregisters the Python half. }
    idx := FindHandler(source);
    if idx >= 0 then
    begin
      Handlers[idx].PyCb := pynone;
      if not SlotIsLive(idx) then DropSlot(idx);
    end;
    InstallHook;
    Exit;
  end;
  idx := EnsureSlot(source);
  if idx < 0 then Exit;
  Handlers[idx].PyCb := cb;
  InstallHook;
end;

function push(source, id: Integer): Boolean;
begin
  Result := IntPush(source, id);
end;

end.

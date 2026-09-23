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
  is deliberately absent and is not blocked on anything here -- it is blocked on
  hardware, because qemu models no GPIO input path at all (measured in
  feature-esp-gpio-and-adc-callback-slices with a control arm: a pull-up input
  reads 0 where silicon reads 1, so the absent edges follow from the absent
  input path). Everything in this unit is exercised on x86-64 against a
  synthetic source instead, which needs no board.

  THE PUMP IS INSTALLED, NOT LINKED IN. `platform.PalPendingDrain` is a nil
  procedure variable that the RTL's blocking points call when it is set; this
  unit assigns it when the FIRST handler is registered. A program that never
  registers one keeps a nil pointer and its behaviour exactly, and DCE can drop
  this whole unit. That is deliberate: making mimic_time `uses interrupts`
  would root the queue in every program that imports `time`, which on ESP is a
  real cost paid by programs that never asked for it.

  NOT BUILT HERE, DELIBERATELY: the owner's "hidden loop" for a script that
  registers handlers and then falls off the end. It needs two things settled
  that this unit does not settle -- it must engage only when a handler is
  registered, and a desktop program must still EXIT -- and getting the second
  wrong hangs every NilPy script that imports this unit at exit on the host,
  which is a regression in ordinary frontend use rather than in an ESP feature.
  The ticket says not to land it in the same commit as the pump. }

interface

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
    delivery -- which nothing on this box can observe. }
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

implementation

uses platform;

type
  THandlerSlot = record
    Source: Integer;
    Cb:     TIntCallback;
  end;

const
  MAX_HANDLERS = 8;

var
  Ring:      array[0 .. INT_RING_CAPACITY - 1] of TIntEvent;
  RingHead:  Integer;   { next slot to read }
  RingCount: Integer;   { how many are queued }
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
  slot := (RingHead + RingCount) mod INT_RING_CAPACITY;
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
  RingCount := RingCount + 1;
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
  RingCount := RingCount - 1;
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

procedure IntOnEvent(source: Integer; cb: TIntCallback);
var idx: Integer;
begin
  idx := FindHandler(source);
  if cb = nil then
  begin
    { unregister: compact, so NHandlers stays the live count }
    if idx >= 0 then
    begin
      while idx < NHandlers - 1 do
      begin
        Handlers[idx] := Handlers[idx + 1];
        idx := idx + 1;
      end;
      NHandlers := NHandlers - 1;
    end;
    InstallHook;
    Exit;
  end;
  if idx >= 0 then
  begin
    Handlers[idx].Cb := cb;
    InstallHook;
    Exit;
  end;
  if NHandlers >= MAX_HANDLERS then
    Exit;
  Handlers[NHandlers].Source := source;
  Handlers[NHandlers].Cb := cb;
  NHandlers := NHandlers + 1;
  InstallHook;
end;

function IntHandlerCount: Integer;
begin
  Result := NHandlers;
end;

function IntPoll: Integer;
var ev: TIntEvent;
    idx, n, lim: Integer;
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
      if Handlers[idx].Cb <> nil then
        Handlers[idx].Cb(ev);
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
  RingCount := 0;
  Dropped := 0;
  Delivered := 0;
  PushSeq := 0;
  InDrain := False;
  for i := 0 to MAX_HANDLERS - 1 do
  begin
    Handlers[i].Source := INT_SRC_NONE;
    Handlers[i].Cb := nil;
  end;
  NHandlers := 0;
  InstallHook;
end;

end.

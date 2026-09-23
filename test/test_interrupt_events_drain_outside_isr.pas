program test_interrupt_events_drain_outside_isr;
{ The PUMP half of feature-s-interrupt-events-reach-python-outside-interrupt-context,
  exercised against a SYNTHETIC source on x86-64. No board, no qemu, no GPIO.

  WHY THE OBVIOUS ASSERTION IS THE WRONG ONE, and the ticket says so in its own
  words: a row asserting only "the callback ran" passes on an implementation
  that runs it in trap context -- the one outcome this whole design exists to
  make impossible -- and on ESP that is diagnosed on silicon at the owner's
  expense. A value check can see neither of the two things that matter. So this
  asserts:

    ORDERING -- nothing is delivered at PUSH time; delivery happens at the
      blocking point and not before it. That is the property that makes
      "outside interrupt context" true, and it is invisible to any count.
    COUNT    -- N pushed, N delivered, and when they differ the drop counter
      accounts for the difference exactly. A dropped edge that nothing counts
      is the plausible-wrong-value failure this repo keeps paying for.

  INT_SRC_TEST is used rather than INT_SRC_GPIO deliberately: nothing on this
  box can observe a real edge, so no row here may be mistakable for evidence
  about edge delivery. }

uses interrupts, mimic_time, sysutils;

var
  seen:      Integer;
  seenSeq:   array[0 .. 255] of Int64;
  reentered: Boolean;
  nested:    Integer;

procedure OnTest(const ev: TIntEvent);
begin
  if seen <= High(seenSeq) then
    seenSeq[seen] := ev.Seq;
  seen := seen + 1;
end;

{ A callback that calls sleep(0) -- the ordinary way a user callback re-enters
  the drain from inside itself. }
procedure OnReentrant(const ev: TIntEvent);
begin
  seen := seen + 1;
  if IntInDrain then
    reentered := True;
  nested := nested + IntPoll;   { must be refused -> contributes 0 }
  mimic_time.sleep(0);           { the pump point, from inside the pump }
end;

var
  i, n, delivered: Integer;
  ev: TIntEvent;
  ok: Boolean;

begin
  { ---- 1. ORDERING: a push delivers NOTHING until a blocking point ------- }
  IntReset;
  seen := 0;
  IntOnEvent(INT_SRC_TEST, @OnTest);
  WriteLn('handlers ', IntHandlerCount);

  for i := 1 to 3 do
    IntPush(INT_SRC_TEST, 40 + i);
  { THE LOAD-BEARING ROW. If this is not 0, a callback ran at push time, which
    on a real target means it ran in trap context. }
  WriteLn('after-push delivered ', IntDelivered, ' pending ', IntPending, ' seen ', seen);

  { BOTH SPELLINGS OF "I AM ABOUT TO BLOCK" MUST PUMP, and they are qualified
    here rather than written bare on purpose. A bare `sleep(0)` binds to
    whichever unit comes LAST in this program's uses clause -- it bound to
    sysutils while that one was unwired, and the row read 0 and looked like a
    broken pump. Listing the units the other way round would have made the same
    fixture pass and hidden the gap. Naming the unit is what makes each row a
    statement about a known routine. }
  mimic_time.sleep(0);   { what `time.sleep` binds to from NilPy }
  WriteLn('after-py-sleep delivered ', IntDelivered, ' pending ', IntPending, ' seen ', seen);

  ok := True;
  for i := 0 to 2 do
    if seenSeq[i] <> Int64(i + 1) then ok := False;
  WriteLn('order-preserved ', ok);

  { the Pascal spelling, on its own events }
  seen := 0;
  IntPush(INT_SRC_TEST, 71);
  WriteLn('before-pas-sleep pending ', IntPending, ' seen ', seen);
  sysutils.Sleep(0);
  WriteLn('after-pas-sleep pending ', IntPending, ' seen ', seen);

  { ---- 2. COUNT: nothing is lost, and what is lost is counted ------------ }
  IntReset;
  seen := 0;
  IntOnEvent(INT_SRC_TEST, @OnTest);
  IntSetDrainBudget(1000);          { take the budget out of this row }
  for i := 1 to INT_RING_CAPACITY do
    IntPush(INT_SRC_TEST, i);
  WriteLn('filled pending ', IntPending, ' dropped ', IntDropped);

  { one past capacity: refused, counted, and NOT silently swallowed }
  ok := IntPush(INT_SRC_TEST, 9999);
  WriteLn('push-when-full ', ok, ' dropped ', IntDropped);

  delivered := IntPoll;
  WriteLn('drained ', delivered, ' seen ', seen, ' pending ', IntPending);
  { pushed = capacity + 1; delivered + dropped must account for ALL of them }
  WriteLn('accounted ', (Int64(delivered) + IntDropped) = Int64(INT_RING_CAPACITY + 1));

  { ---- 3. BUDGET: a fast source cannot starve the sleeper ---------------- }
  IntReset;
  seen := 0;
  IntOnEvent(INT_SRC_TEST, @OnTest);
  IntSetDrainBudget(4);
  for i := 1 to 10 do
    IntPush(INT_SRC_TEST, i);
  n := IntPoll;
  WriteLn('budget-bounded ', n, ' pending-after ', IntPending);
  { deferred, NOT lost: the rest are still queued and a later drain takes them }
  n := IntPoll;
  WriteLn('second-drain ', n, ' pending-after ', IntPending);

  { ---- 4. RE-ENTRANCY: refused, and the outer count stays true ----------- }
  IntReset;
  seen := 0;
  reentered := False;
  nested := 0;
  IntSetDrainBudget(1000);
  IntOnEvent(INT_SRC_TEST, @OnReentrant);
  for i := 1 to 3 do
    IntPush(INT_SRC_TEST, i);
  delivered := IntPoll;
  WriteLn('reentrant-observed ', reentered, ' nested-delivered ', nested);
  WriteLn('outer-delivered ', delivered, ' seen ', seen, ' pending ', IntPending);

  { ---- 5. THE HOOK IS NOT INSTALLED WHEN NOBODY REGISTERS ---------------- }
  { The negative control for the whole design: with no handler, a blocking
    point must do exactly what it did before this feature existed. If this
    row ever reports a delivery, the pump is running in programs that never
    asked for it -- which is the cost the nil-hook design exists to avoid. }
  IntReset;
  seen := 0;
  WriteLn('no-handler handlers ', IntHandlerCount);
  IntPush(INT_SRC_TEST, 1);
  mimic_time.sleep(0);
  WriteLn('no-handler delivered ', IntDelivered, ' pending ', IntPending, ' seen ', seen);

  { ---- 6. ITERATOR: drains without running callbacks --------------------- }
  IntReset;
  seen := 0;
  IntOnEvent(INT_SRC_TEST, @OnTest);
  IntPush(INT_SRC_TEST, 7);
  IntPush(INT_SRC_TEST, 8);
  n := 0;
  while IntNext(ev) do
  begin
    n := n + 1;
    WriteLn('ev source ', ev.Source, ' id ', ev.Id, ' seq ', ev.Seq);
  end;
  WriteLn('iterated ', n, ' callbacks-run ', seen, ' pending ', IntPending);

  WriteLn('INTERRUPT-PUMP-OK');
end.

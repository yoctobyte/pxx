{ SPDX-License-Identifier: Zlib }
program EspBoardGpioPollDrain;
{ BOARD ONLY (ESP32-S3 or ESP32-C3): interrupts.poll() IS a drain point, and the
  budget defers rather than drops.

    PXX=$PWD/compiler/pascal26 PXX_MAIN=$PWD/test/esp_board_gpio_poll_drain.pas \
      tools/esp_flash.sh --project examples/esp32/gpio-edge-s3 --no-verify --seconds 25

  (For the C3, --project examples/esp32/gpio-edge-c3. Through a gpio-edge
  project and not the bare <prog.pas> form for the same reason the ring stress
  is: the image links pylib, which needs a bigger app partition than hello-*.)

  WHY THIS EXISTS, given examples/esp32/gpio-edge-{c3,s3} already run on a
  board. Those drain with time.sleep(), and the owner's settled model is "the
  ISR runs in C/Pascal, and Python drains the event in the main task at sleep
  and blocking points, PLUS poll()". The poll() half was verified only by
  HOSTED tests (test_interrupt_events_reach_python.npy,
  test_interrupt_events_drain_outside_isr.pas,
  test_interrupts_pascal_no_pylib.pas) -- never on silicon, where the ISR is a
  real interrupt rather than a function call. This closes that gap and nothing
  else; it deliberately does not re-test what gpio-edge already covers.

  THE FOUR CLAIMS, and what makes each one falsifiable:

    ORDERING   After the edges, with NO blocking point and NO poll, the handler
               has not run: delivered = 0 and Seen = 0 while pending > 0. An
               implementation that ran handlers in the ISR fails here. This
               repeats gpio-edge's first row on purpose -- it is the baseline
               the poll claim is measured against, and a poll that "delivered"
               events already delivered at edge time would prove nothing.

    POLL       One IntPoll, with no sleep anywhere in the program before it,
               delivers events and returns how many. This is the row that does
               not exist on silicon today.

    BUDGET     With MORE pending than IntDrainBudget (default 16), one IntPoll
               delivers EXACTLY the budget and the remainder stays PENDING --
               deferred, not dropped. Asserted against IntDrainBudget as read
               at run time, not against the literal 16, so a changed default
               does not silently turn this row green-for-the-wrong-reason.
               This is a different bound from the ring's: the 64-slot ring
               DROPS (and counts) on overflow, the budget DEFERS. Conflating
               the two is how "events are never lost" gets said.

    NESTED     IntPoll called from inside a handler returns 0 and IntInDrain is
               True there. A re-entrant drain would let a nested call consume
               events its caller then reports as delivered.

  ACCOUNTING is checked after every phase: GpioEdgeCount = IntDelivered +
  IntDropped, where the edge count is kept by espgpio's ISR and not by the
  ring, so the two sides of the equation have independent producers.

  NO WIRING NEEDED. The pin is INPUT_OUTPUT and the pad drives its own input
  path, so each write is an edge the GPIO hardware sees. Under QEMU this
  program gets NO edges at all (QEMU models no GPIO input path), so it cannot
  be run there -- it reports POLL-DRAIN-NO-EDGES and fails rather than passing
  vacuously, because a run that sees zero edges satisfies every invariant above
  trivially and would otherwise be the purest possible guard that cannot fail.

  MEASURED 2026-09-28 by frankb-12 on real silicon, v450 (tree 3503825c2f,
  compiler binary c19cc2d531e4 as esp_flash stamps it). ESP32-C3 and ESP32-S3
  gave IDENTICAL output, rc=0:

    POLL-DRAIN setup rc=0
    POLL-DRAIN budget=16
    POLL-DRAIN after-edges isr=10 pending=10 delivered=0 seen=0
    POLL-DRAIN poll1 returned=10 seen=10 pending=0
    POLL-DRAIN over-budget isr-added=40 pending=40 dropped=0
    POLL-DRAIN poll2 returned=16 budget=16 pending-left=24
    POLL-DRAIN drained-total=40 polls=3 pending=0
    POLL-DRAIN nested rc=0 in-drain=1
    POLL-DRAIN final isr=53 delivered=53 dropped=0 seen=53
    POLL-DRAIN-DONE failures=0

  Read three things out of that. 40 edges into the 64-slot ring DROPPED NOTHING,
  and one poll took exactly the budget and left 24 PENDING: deferred, not lost,
  which is a different bound from the ring's overflow and the one people
  conflate. 10 + 40 + 3 = 53 edges made, and isr = delivered = seen = 53 with
  dropped 0, so the accounting closes. And the drain took 3 polls
  (16 + 16 + 8 = 40), not one, which is what "a drain point is a bounded amount
  of work" means in practice. }

uses interrupts, espgpio;

procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure esp_rom_delay_us(us: Integer); external;

const
  PIN = 5;
  { Below the budget, so one poll takes them all. }
  N_SMALL = 10;
  { Above the budget (16) and below the ring (64), so the budget row sees a
    remainder and NOTHING is dropped -- which is what makes "deferred" and
    "dropped" distinguishable in the same run. }
  N_OVER = 40;
  { The ISR must get to run between edges: the GPIO status bit is a latch, so
    two edges before the ISR clears it are one interrupt. }
  GAP_US = 60;

var
  Seen, BadId, NestedRc: Integer;
  NestedSeenInDrain: Boolean;
  ProbeNested: Boolean;
  Failures: Integer;

procedure OnEdge(const ev: TIntEvent);
begin
  Seen := Seen + 1;
  if ev.Id <> PIN then
    BadId := BadId + 1;
  { Only on the dedicated phase, so the ordinary rows are not perturbed by a
    nested call that is refused anyway. }
  if ProbeNested then
  begin
    NestedSeenInDrain := IntInDrain;
    NestedRc := IntPoll;
    ProbeNested := False;
  end;
end;

{ One rising edge per call: drive low, settle, drive high, settle. Armed for
  RISING only, so the edge count is one per pulse rather than two. }
procedure Pulse;
begin
  GpioSetLevel(PIN, 0);
  esp_rom_delay_us(GAP_US);
  GpioSetLevel(PIN, 1);
  esp_rom_delay_us(GAP_US);
end;

procedure Pulses(n: Integer);
var i: Integer;
begin
  for i := 1 to n do
    Pulse;
end;

procedure Check(ok: Boolean);
begin
  if not ok then
    Failures := Failures + 1;
end;

var
  rc, budget, isr0, isr1, firstPoll, secondPoll, pend, drained, guard: Integer;
begin
  Failures := 0;
  rc := GpioSetDirection(PIN, GPIO_MODE_INPUT_OUTPUT);
  GpioSetLevel(PIN, 0);
  IntOnEvent(INT_SRC_GPIO, @OnEdge);
  rc := rc + GpioArmEdge(PIN, GPIO_EDGE_RISING);
  esp_rom_printf('POLL-DRAIN setup rc=%d'#10, rc);
  Check(rc = 0);

  budget := IntDrainBudget;
  esp_rom_printf('POLL-DRAIN budget=%d'#10, budget);
  Check(budget > 0);

  { ---- ORDERING: edges, then nothing. No sleep, no poll. ---- }
  Pulses(N_SMALL);
  isr0 := GpioEdgeCount;
  esp_rom_printf('POLL-DRAIN after-edges isr=%d', isr0);
  esp_rom_printf(' pending=%d', IntPending);
  esp_rom_printf(' delivered=%d', Integer(IntDelivered));
  esp_rom_printf(' seen=%d'#10, Seen);

  { A run with no edges satisfies everything below trivially. Refuse it. }
  if isr0 = 0 then
  begin
    esp_rom_printf('POLL-DRAIN-NO-EDGES isr=%d'#10, isr0);
    esp_rom_printf('POLL-DRAIN-DONE failures=%d'#10, 1);
    Halt(1);
  end;

  Check(Seen = 0);
  Check(IntDelivered = 0);
  Check(IntPending > 0);

  { ---- POLL: one call, and it is the first blocking-ish point in the program.
    Nothing above called sleep or delay-with-yield; esp_rom_delay_us busy-waits
    and does not yield, which is what makes this row about poll(). ---- }
  firstPoll := IntPoll;
  esp_rom_printf('POLL-DRAIN poll1 returned=%d', firstPoll);
  esp_rom_printf(' seen=%d', Seen);
  esp_rom_printf(' pending=%d'#10, IntPending);
  Check(firstPoll > 0);
  Check(Seen = firstPoll);
  Check(IntPending = 0);
  Check(Integer(IntDelivered) = firstPoll);
  Check(BadId = 0);
  Check(GpioEdgeCount = Integer(IntDelivered) + Integer(IntDropped));

  { ---- BUDGET: more pending than the budget. One poll takes exactly the
    budget; the rest stay PENDING, and nothing is dropped. ---- }
  isr1 := GpioEdgeCount;
  Pulses(N_OVER);
  pend := IntPending;
  esp_rom_printf('POLL-DRAIN over-budget isr-added=%d', GpioEdgeCount - isr1);
  esp_rom_printf(' pending=%d', pend);
  esp_rom_printf(' dropped=%d'#10, Integer(IntDropped));
  Check(pend > budget);

  secondPoll := IntPoll;
  esp_rom_printf('POLL-DRAIN poll2 returned=%d', secondPoll);
  esp_rom_printf(' budget=%d', budget);
  esp_rom_printf(' pending-left=%d'#10, IntPending);
  { EXACTLY the budget, compared against the budget read at run time. }
  Check(secondPoll = budget);
  Check(IntPending = pend - budget);
  Check(IntPending > 0);

  { Deferred, not dropped: repeated polls take the remainder, with no edges
    made in between. The guard bounds the loop so a broken poll cannot hang the
    board instead of failing. }
  drained := secondPoll;
  guard := 0;
  while (IntPending > 0) and (guard < 100) do
  begin
    drained := drained + IntPoll;
    guard := guard + 1;
  end;
  esp_rom_printf('POLL-DRAIN drained-total=%d', drained);
  esp_rom_printf(' polls=%d', guard + 1);
  esp_rom_printf(' pending=%d'#10, IntPending);
  Check(IntPending = 0);
  Check(guard < 100);
  Check(Seen = Integer(IntDelivered));
  Check(GpioEdgeCount = Integer(IntDelivered) + Integer(IntDropped));

  { ---- NESTED: a poll from inside a handler is refused. ---- }
  ProbeNested := True;
  NestedRc := -1;
  NestedSeenInDrain := False;
  Pulses(3);
  IntPoll;
  { Drain whatever the budget left, so the accounting row below is clean. }
  guard := 0;
  while (IntPending > 0) and (guard < 100) do
  begin
    IntPoll;
    guard := guard + 1;
  end;
  esp_rom_printf('POLL-DRAIN nested rc=%d', NestedRc);
  esp_rom_printf(' in-drain=%d'#10, Ord(NestedSeenInDrain));
  Check(NestedRc = 0);
  Check(NestedSeenInDrain);

  { ---- Done. Disarm, final accounting. ---- }
  GpioArmEdge(PIN, GPIO_EDGE_NONE);
  esp_rom_printf('POLL-DRAIN final isr=%d', GpioEdgeCount);
  esp_rom_printf(' delivered=%d', Integer(IntDelivered));
  esp_rom_printf(' dropped=%d', Integer(IntDropped));
  esp_rom_printf(' seen=%d'#10, Seen);
  Check(GpioEdgeCount = Integer(IntDelivered) + Integer(IntDropped));
  Check(Seen = Integer(IntDelivered));

  esp_rom_printf('POLL-DRAIN-DONE failures=%d'#10, Failures);
  if Failures > 0 then
    Halt(1);
end.

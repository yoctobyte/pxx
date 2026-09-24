{ SPDX-License-Identifier: Zlib }
program EspBoardGpioRingStress;
{ BOARD ONLY (ESP32-S3, dual core): does the interrupts ring stay exact while
  GPIO edges pre-empt its consumer at arbitrary instructions?

    PXX=$PWD/compiler/pascal26 PXX_MAIN=$PWD/test/esp_board_gpio_ring_stress.pas \
      tools/esp_flash.sh --project examples/esp32/gpio-edge-s3 --no-verify --seconds 45

  Through gpio-edge-s3's project and not the bare `<prog.pas>` form: the image
  links pylib (interrupts' Python surface), which needs --xtensa-long-calls and
  more than hello-s3's 1 MB app partition.

  examples/esp32/gpio-edge-s3 cannot answer that: every edge there is made by
  the consumer task itself, so an edge never lands INSIDE IntNext. Here a
  FreeRTOS task pinned to CORE 1 toggles the pin nonstop, the GPIO ISR runs
  on CORE 0 (the core that installed the ISR service, i.e. app_main's), and
  the main task on core 0 drains as tightly as it can. So ISRs pre-empt
  the consumer at arbitrary points, including inside IntNext.

  Checks, per run:
    COUNT      ISR entries == delivered + dropped (pending drained to 0).
    PLACEMENT  delivered events carry Seq 1, 2, 3, ... with no gap and no
               repeat. A push written to the wrong slot, or a slot read before
               it was filled, shows up here as a Seq out of step.
  The ISR entry count is kept by espgpio's ISR, not by the ring.

  -dOLDRING builds against the pre-0d5df8991 ring as a POSITIVE CONTROL
  (PXX_EXTRA_FLAGS="-dOLDRING -Fu<dir>", where <dir> holds that interrupts.pas
  with `INT_RING_OLD = 1;` added to its interface). The reference to
  INT_RING_OLD below fails the build if the new copy was picked instead.

  MEASURED 2026-09-24, ESP32-S3 board, 20 s, compiler 5cb3fdf5896b:
    NEW  isr=671997 delivered=347861 dropped=324136  misplaced=0     exact
    NEW  isr=671997 delivered=347858 dropped=324139  misplaced=0     exact
    OLD  isr=671997 delivered=354922 dropped=314572  misplaced=3667  BROKEN
  In OLD, 2,503 edges are neither delivered nor dropped. About half of all
  edges are dropped in every run, which is what keeps the consumer inside
  IntNext while the ISR fires. }

uses interrupts, espgpio;

procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure esp_rom_delay_us(us: Integer); external;
procedure vTaskDelay(ticks: Integer); external;
function esp_timer_get_time: Int64; external;
procedure vTaskDelete(handle: Pointer); external;
function xTaskCreatePinnedToCore(fn: Pointer; name: PChar; stackDepth: Integer;
  arg: Pointer; prio: Integer; handle: Pointer; core: Integer): Integer; external;

const
  PIN = 5;
  RUN_SECONDS = 20;
  { 3 us live-locked core 0, measured: a GPIO interrupt that re-pends faster
    than it is serviced leaves no cycles for anything else there, and the run
    printed nothing past setup for 60 s -- no watchdog line either. }
  HALF_PERIOD_US = 25;

var
  Stop, ProducerDone: Boolean;
  Toggles: Integer;
  LastSeq: Int64;
  Misplaced, BadId, Seen: Integer;
  TaskName: array[0..4] of Char = ('e', 'd', 'g', 'e', #0);

{ CORE 1. Makes edges until told to stop. Yields one tick every ~10 ms so
  core 1's idle task feeds the task watchdog. }
procedure Producer(arg: Pointer);
var i: Integer;
begin
  while not Stop do
  begin
    for i := 1 to 1000 do
    begin
      GpioSetLevel(PIN, 1);
      esp_rom_delay_us(HALF_PERIOD_US);
      GpioSetLevel(PIN, 0);
      esp_rom_delay_us(HALF_PERIOD_US);
    end;
    Toggles := Toggles + 2000;
    vTaskDelay(1);
  end;
  ProducerDone := True;
  vTaskDelete(nil);
end;

procedure OnEdge(const ev: TIntEvent);
begin
  if ev.Seq <> LastSeq + 1 then
    Misplaced := Misplaced + 1;
  LastSeq := ev.Seq;
  if ev.Id <> PIN then
    BadId := BadId + 1;
  Seen := Seen + 1;
end;

var
  rc, k, secs, nextBeat: Integer;
  t0: Int64;
begin
{$ifdef OLDRING}
  esp_rom_printf('RING-STRESS variant OLD (Head+Count, plain decrement) %d'#10, INT_RING_OLD);
{$else}
  esp_rom_printf('RING-STRESS variant NEW (producer tail, atomic count) %d'#10, 0);
{$endif}
  rc := GpioSetDirection(PIN, GPIO_MODE_INPUT_OUTPUT);
  GpioSetLevel(PIN, 0);
  IntOnEvent(INT_SRC_GPIO, @OnEdge);
  rc := rc + GpioArmEdge(PIN, GPIO_EDGE_ANY);
  esp_rom_printf('RING-STRESS setup rc=%d'#10, rc);

  rc := xTaskCreatePinnedToCore(@Producer, @TaskName[0], 4096, nil, 5, nil, 1);
  esp_rom_printf('RING-STRESS producer task created=%d'#10, rc);

  { CORE 0: drain as tightly as possible, for RUN_SECONDS of wall time
    (esp_timer, not a round count -- how long a round takes depends on how
    much the ISR load steals, which is the thing under test). One tick per
    round so core 0's idle task runs too. }
  t0 := esp_timer_get_time;
  nextBeat := 1;
  repeat
    for k := 1 to 2000 do
      IntPoll;
    vTaskDelay(1);
    secs := Integer((esp_timer_get_time - t0) div 1000000);
    if secs >= nextBeat then
    begin
      esp_rom_printf('RING-STRESS heartbeat s=%d', secs);
      esp_rom_printf(' isr=%d', GpioEdgeCount);
      esp_rom_printf(' delivered=%d', Integer(IntDelivered));
      esp_rom_printf(' dropped=%d'#10, Integer(IntDropped));
      nextBeat := secs + 5;
    end;
  until secs >= RUN_SECONDS;

  Stop := True;
  while not ProducerDone do vTaskDelay(1);
  GpioArmEdge(PIN, GPIO_EDGE_NONE);
  while IntPending > 0 do IntPoll;

  esp_rom_printf('RING-STRESS toggles=%d', Toggles);
  esp_rom_printf(' isr=%d', GpioEdgeCount);
  esp_rom_printf(' delivered=%d', Integer(IntDelivered));
  esp_rom_printf(' dropped=%d', Integer(IntDropped));
  esp_rom_printf(' pending=%d'#10, IntPending);
  esp_rom_printf('RING-STRESS misplaced=%d', Misplaced);
  esp_rom_printf(' bad-id=%d', BadId);
  esp_rom_printf(' seen=%d'#10, Seen);
  if (Int64(GpioEdgeCount) = IntDelivered + IntDropped) and (Misplaced = 0)
     and (BadId = 0) and (Int64(Seen) = IntDelivered) then
    esp_rom_printf('RING-STRESS VERDICT exact %d'#10, 0)
  else
    esp_rom_printf('RING-STRESS VERDICT BROKEN %d'#10, 0);
  esp_rom_printf('RING-STRESS-COMPLETE %d'#10, 0);
  while True do vTaskDelay(1000);
end.

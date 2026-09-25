{ SPDX-License-Identifier: 0BSD }
program Esp32IsrCtx;
{ THE ASYMMETRY PROBE for feature-n-a-non-allocating-restricted-thunk-for-an-isr.

  One question: does a pxx routine dispatched by esp_timer's ISR method
  actually run in interrupt context, and can pxx SEE that it does?

  WHY A PAIR AND NOT A READING. frankb-8e measured the task-dispatch arm on
  both ISAs and got 0 everywhere -- app_main 0, timer callback 0, esp32c3 and
  esp32s3, ~400 callbacks each. Four clean rows, and they establish nothing
  about the INSTRUMENT: "every context here is task context" and
  "xPortInIsrContext always returns 0" predict those rows identically. More
  rows of the same arm add confidence about the arm and none about the
  instrument -- a wider clean sweep is the more seductive version of that trap,
  because it reads like corroboration.

  Only a NON-ZERO reading separates the two, and the ISR dispatch method is the
  one place in this project that can produce one. So this program registers
  BOTH dispatch methods in ONE image and reports both: the task arm reproduces
  8e's 0 and the ISR arm must not. The asymmetry is the result; neither half is
  a result alone.

  ONE IMAGE, ONE BOOT, ON PURPOSE. Two separate runs would compare two
  binaries, two boots and two qemu invocations, and any of those could differ
  for reasons having nothing to do with dispatch. Here the two readings come
  from the same instrument in the same image microseconds apart, and the ONLY
  declared difference between them is the dispatch_method byte.

  THE SENTINEL IS -1 AND IT IS LOAD-BEARING. A callback that never fires leaves
  its slot untouched. Initialised to 0 that is indistinguishable from "fired,
  and correctly read task context" -- the expected value of the passing arm
  collides with the value of the machinery doing nothing at all. -1 cannot be
  produced by xPortInIsrContext on either port, so a slot still holding it says
  NOT FIRED and nothing else. The hit counters are the same guard from the
  other side.

  ASSERT <> 0, NEVER = 1 (frankb-8e). The two ports return different
  quantities: riscv's xPortInIsrContext returns the raw nesting count
  (port.c:461/469, and portasm.S:607 branches on `> 0` in terms, so nesting is
  real there and not theoretical), while xtensa normalises to a boolean. A row
  pinning 1 passes on xtensa and can fail on riscv the first time a second
  interrupt arrives during the first -- correct on every run until it is not.
  The count itself is printed as an observation, never asserted.

  Expected qemu output:
    PXX isrctx: main ctx=0
    PXX isrctx: task hits=5 ctx=0
    PXX isrctx: isr  hits=5 ctx=1
    PXX isrctx: PAIR OK status=0 }

{ esp_timer, declared here rather than through the esptimer unit: that unit
  hardcodes dispatch_method := ESP_TIMER_TASK (esptimer.pas, EnsureCreated),
  which is the arm this program exists to contrast against. Widening the unit
  before knowing the answer would put the thing under test inside the library
  that the test is supposed to justify. }
function esp_timer_create(args: Pointer; outHandle: Pointer): Integer; external;
function esp_timer_start_periodic(handle: Pointer; periodUs: Int64): Integer; external;
function esp_timer_stop(handle: Pointer): Integer; external;
function esp_timer_delete(handle: Pointer): Integer; external;

procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure vTaskDelay(ticks: Integer); external;

{ FreeRTOS's context predicate. BaseType_t is a 32-bit signed int on both
  ports; see the header comment for what each one actually returns. }
function xPortInIsrContext: Integer; external;

const
  ESP_TIMER_TASK = 0;
  ESP_TIMER_ISR  = 1;   { only a valid enumerator when the Kconfig option is
                          on -- see sdkconfig.defaults }
  NOT_FIRED      = -1;

type
  { mirrors esp_timer_create_args_t (riscv32/ILP32: 4-byte pointers/ints) }
  TEspTimerCreateArgs = record
    callback:        Pointer;
    arg:             Pointer;
    dispatch_method: Integer;
    name:            Pointer;
    skip_unhandled:  Byte;
    pad0, pad1, pad2: Byte;
  end;

var
  taskCtx, isrCtx:   Integer;
  taskHits, isrHits: Integer;
  taskName: array[0..4] of Char = ('t', 'a', 's', 'k', #0);
  isrName:  array[0..3] of Char = ('i', 's', 'r', #0);

{ Task-dispatch callback: reproduces 8e's arm inside this image, so the 0 it
  reports is this instrument's 0 and not a number carried over from another
  build. Plain routine -- the esp_timer dispatch task has no IRAM requirement. }
procedure OnTaskTick(arg: Pointer);
begin
  taskCtx := xPortInIsrContext;
  taskHits := taskHits + 1;
end;

{ ISR-dispatch callback. `iram;` is REQUIRED and not decoration: this runs from
  timer_alarm_handler, which is ESP_TIMER_IRAM_ATTR (esp_timer.c:474), and a
  handler that touches flash during a flash operation faults. It also does the
  least work that can answer the question -- one read, one increment, no
  printing, no allocation -- because the whole point of the parent ticket is
  what an ISR body may not do. }
procedure OnIsrTick(arg: Pointer); iram;
begin
  isrCtx := xPortInIsrContext;
  isrHits := isrHits + 1;
end;

{ Create and start one periodic timer with the given dispatch method, handing
  its handle back in `h` (nil if it was never created) so the caller can stop
  and DELETE it. Returns 0 on success, or the failing SDK rc (nonzero) so the
  caller can report WHICH half failed rather than a bare false. }
function StartOne(cb: Pointer; nm: Pointer; dispatch, ms: Integer;
                  var h: Pointer): Integer;
var
  args: TEspTimerCreateArgs;
  rc: Integer;
begin
  args.callback := cb;
  args.arg := nil;
  args.dispatch_method := dispatch;
  args.name := nm;
  args.skip_unhandled := 0;
  args.pad0 := 0; args.pad1 := 0; args.pad2 := 0;
  h := nil;
  rc := esp_timer_create(@args, @h);
  if rc <> 0 then
  begin
    StartOne := rc;
    Exit;
  end;
  StartOne := esp_timer_start_periodic(h, Int64(ms) * 1000);
end;

var
  mainCtx, waited, status, rc: Integer;
  taskTimer, isrTimer: Pointer;
begin
  taskCtx := NOT_FIRED;
  isrCtx  := NOT_FIRED;
  taskHits := 0;
  isrHits  := 0;
  status   := 0;

  { app_main is an ordinary FreeRTOS task. If this is not 0 the instrument is
    not measuring what its name says and every other row is void, so it is
    checked first and reported even when it is right. }
  mainCtx := xPortInIsrContext;
  esp_rom_printf('PXX isrctx: main ctx=%d'#10, mainCtx);
  if mainCtx <> 0 then status := status or 1;

  rc := StartOne(@OnTaskTick, @taskName[0], ESP_TIMER_TASK, 100, taskTimer);
  if rc <> 0 then
  begin
    status := status or 2;
    esp_rom_printf('PXX isrctx: task create/start failed rc=%d'#10, rc);
  end;

  { A nonzero rc HERE is the informative failure: it is what a build without
    CONFIG_ESP_TIMER_SUPPORTS_ISR_DISPATCH_METHOD produces, because 1 is then
    ESP_TIMER_MAX rather than ESP_TIMER_ISR. Reported separately from the task
    arm for exactly that reason. }
  rc := StartOne(@OnIsrTick, @isrName[0], ESP_TIMER_ISR, 100, isrTimer);
  if rc <> 0 then
  begin
    status := status or 4;
    esp_rom_printf('PXX isrctx: ISR create/start failed rc=%d'#10, rc);
  end;

  { Wait for both to have fired at least 5 times, bounded so a dead timer
    still reports rather than hanging the run out to the timeout. }
  waited := 0;
  while ((taskHits < 5) or (isrHits < 5)) and (waited < 100) do
  begin
    vTaskDelay(10);
    waited := waited + 1;
  end;

  esp_rom_printf('PXX isrctx: task hits=%d', taskHits);
  esp_rom_printf(' ctx=%d'#10, taskCtx);
  esp_rom_printf('PXX isrctx: isr  hits=%d', isrHits);
  esp_rom_printf(' ctx=%d'#10, isrCtx);

  { THE PAIR. Each clause is here because dropping it admits a different way of
    being wrong:
      hits > 0          -- a slot still at -1 never fired, and a comparison
                           against a value that was never written is not a
                           measurement of anything.
      taskCtx  = 0      -- reproduces 8e's baseline in THIS image.
      isrCtx  <> 0      -- the discriminating half, and the only row in either
                           of our arms that can come out non-zero.
    An all-zero instrument fails the third; a stuck-non-zero one fails the
    second; a silent timer fails the first. }
  if (taskHits <= 0) or (isrHits <= 0) then status := status or 8;
  if taskCtx <> 0 then status := status or 16;
  if isrCtx = 0 then status := status or 32;
  if isrCtx = NOT_FIRED then status := status or 64;

  if status = 0 then
    esp_rom_printf('PXX isrctx: PAIR OK status=%d'#10, status)
  else
    esp_rom_printf('PXX isrctx: PAIR FAILED status=%d'#10, status);

  { Release both timers. esp_timer_create allocates each one from the heap and
    only esp_timer_delete gives it back (a running timer must be stopped
    first), so an example that stops here without it teaches its readers to
    leak: a heap soak of this program read 72 B per run, 2026-09-25. }
  if taskTimer <> nil then
  begin
    esp_timer_stop(taskTimer);
    esp_timer_delete(taskTimer);
  end;
  if isrTimer <> nil then
  begin
    esp_timer_stop(isrTimer);
    esp_timer_delete(isrTimer);
  end;

  { park politely so the FreeRTOS idle task keeps feeding the WDT }
  while True do
    vTaskDelay(1000);
end.

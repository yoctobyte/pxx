{ SPDX-License-Identifier: Zlib }
program EspBoardIsrNoAlloc;
{ BOARD ONLY (ESP32-S3): our interrupt handlers do not ALLOCATE.
  (feature-esp-hardware-flash-validation, row 2's real contract.)

    PXX=$PWD/compiler/pascal26 PXX_MAIN=$PWD/test/esp_board_isr_no_alloc.pas \
      tools/esp_flash.sh --project examples/esp32/adc-s3 --no-verify --seconds 20

  "The ISR fired" passes whether or not a handler allocates, and an allocation
  in interrupt context faults later on another context's heap. So this test
  asserts on the ALLOCATOR: IDF's free-heap figure is read before and after
  thousands of ISR entries while the main task is parked in vTaskDelay, so
  nothing on our side allocates, and the heap's integrity is checked after.
    idle    the same window with no interrupts: the drift floor
    gpio    ~10,000 espgpio edge ISRs (count + IntPush), from a core-1 producer
    adc     ~600 espadc conversion-done ISRs (count + IntPush), at 20 kHz
  The ring fills and then drops; no drain runs. That is deliberate: a drain
  would run handlers, which is task context and may allocate.

  -dALLOC_IN_ISR is the POSITIVE CONTROL: the gpio phase's ISR is swapped for
  one that also GetMems 16 bytes and keeps them, so the free heap must fall
  by at least 16 bytes per entry. If it does not fall, this instrument cannot
  see an allocation and its zero means nothing.
  MEASURED: it does not get that far. The first allocation in the ISR aborts
  the chip ("pxx: out of memory (ESP-IDF heap exhausted)", then reboot, in a
  loop), so an ISR allocation on this path is LOUD, and that message
  misnames the cause. Because it aborts, it never exercises the readout, so:

  -dALLOC_IN_TASK is the READOUT's control: the main task GetMems 16 B x 1000
  during the gpio window, so heap-delta must be >= 16000. It proves the
  free-heap figure sees allocations of this size; the zeros above are real
  zeros. }

uses interrupts, espgpio, espadc;

procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure esp_rom_delay_us(us: Integer); external;
procedure vTaskDelay(ticks: Integer); external;
procedure vTaskDelete(handle: Pointer); external;
function xTaskCreatePinnedToCore(fn: Pointer; name: PChar; stackDepth: Integer;
  arg: Pointer; prio: Integer; handle: Pointer; core: Integer): Integer; external;
function esp_get_free_heap_size: LongWord; external;
function heap_caps_check_integrity_all(printErrors: Boolean): Boolean; external;
function gpio_isr_handler_remove(pin: Integer): Integer; external;
function gpio_isr_handler_add(pin: Integer; isr: Pointer; arg: Pointer): Integer; external;

const
  PIN = 5;
  EDGES_PER_BURST = 1000;   { x2 edges (any-edge), 5 bursts ~ 10,000 ISRs }
  BURSTS = 5;

var
  Go, Done: Boolean;
  TaskName: array[0..4] of Char = ('e', 'd', 'g', 'e', #0);
{$ifdef ALLOC_IN_ISR}
  AllocIsrCount: Integer;
{$endif}

{ CORE 1: waits for Go, makes the edges, sets Done, then idles (deleting
  itself would free its stack and move the heap figure we are reading). }
procedure Producer(arg: Pointer);
var b, i: Integer;
begin
  while not Go do vTaskDelay(1);
  for b := 1 to BURSTS do
  begin
    for i := 1 to EDGES_PER_BURST do
    begin
      GpioSetLevel(PIN, 1);
      esp_rom_delay_us(25);
      GpioSetLevel(PIN, 0);
      esp_rom_delay_us(25);
    end;
    vTaskDelay(1);
  end;
  Done := True;
  while True do vTaskDelay(1000);
end;

{$ifdef ALLOC_IN_ISR}
procedure AllocIsr(arg: Pointer);
var p: Pointer;
begin
  AllocIsrCount := AllocIsrCount + 1;
  GetMem(p, 16);   { kept on purpose: the control must move the heap }
  IntPush(INT_SRC_GPIO, PIN);
end;
{$endif}

procedure Report(phase: string; before, after: LongWord; isrs: Integer);
begin
  esp_rom_printf(phase, 0);
  esp_rom_printf(' isrs=%d', isrs);
  esp_rom_printf(' heap-delta=%d', Integer(before) - Integer(after));
  esp_rom_printf(' integrity=%d'#10, Ord(heap_caps_check_integrity_all(True)));
end;

var
  h0, h1: LongWord;
  e0, f0: Integer;
{$ifdef ALLOC_IN_TASK}
  e1: Integer;
  keep: Pointer;
{$endif}
begin
  GpioSetDirection(PIN, GPIO_MODE_INPUT_OUTPUT);
  GpioSetLevel(PIN, 0);
  GpioArmEdge(PIN, GPIO_EDGE_ANY);
{$ifdef ALLOC_IN_ISR}
  gpio_isr_handler_remove(PIN);
  gpio_isr_handler_add(PIN, @AllocIsr, nil);
  esp_rom_printf('ISR-NOALLOC variant CONTROL (ISR allocates 16 B) %d'#10, 0);
{$else}
  esp_rom_printf('ISR-NOALLOC variant REAL (espgpio / espadc handlers) %d'#10, 0);
{$endif}
  xTaskCreatePinnedToCore(@Producer, @TaskName[0], 4096, nil, 5, nil, 1);
  vTaskDelay(20);   { let the task's own allocations settle }

  { idle: the drift floor over a comparable window }
  h0 := esp_get_free_heap_size;
  vTaskDelay(50);
  h1 := esp_get_free_heap_size;
  Report('ISR-NOALLOC idle', h0, h1, 0);

  { gpio }
  e0 := GpioEdgeCount;
  h0 := esp_get_free_heap_size;
  Go := True;
{$ifdef ALLOC_IN_TASK}
  for e1 := 1 to 1000 do GetMem(keep, 16);
  esp_rom_printf('ISR-NOALLOC variant CONTROL (task allocates 16 B x 1000) %d'#10, 0);
{$endif}
  while not Done do vTaskDelay(1);
  h1 := esp_get_free_heap_size;
{$ifdef ALLOC_IN_ISR}
  Report('ISR-NOALLOC gpio', h0, h1, AllocIsrCount);
{$else}
  Report('ISR-NOALLOC gpio', h0, h1, GpioEdgeCount - e0);
{$endif}
  GpioArmEdge(PIN, GPIO_EDGE_NONE);

  { adc: start first (start allocates, in task context), then measure }
  esp_rom_printf('ISR-NOALLOC adc start rc=%d'#10, AdcStart(0, 20000));
  vTaskDelay(20);
  f0 := AdcFrameCount;
  h0 := esp_get_free_heap_size;
  vTaskDelay(200);
  h1 := esp_get_free_heap_size;
  Report('ISR-NOALLOC adc', h0, h1, AdcFrameCount - f0);
  AdcStop;

  esp_rom_printf('ISR-NOALLOC-COMPLETE %d'#10, 0);
  while True do vTaskDelay(1000);
end.

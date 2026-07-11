{ SPDX-License-Identifier: 0BSD }
program Esp32Timer;
{ esptimer event-surface demo (feature-esp-peripheral-callback-api slice 1):
  a periodic esp_timer callback counts ticks, app_main polls the counter and
  reports. The app code never touches esp_timer_create/esp_intr_alloc — only
  the library's TimerInit / OnElapsed / TimerStartPeriodicMs surface.

  KNOWN WART: the callback carries `iram;` ONLY because taking a plain proc's
  address in a relocatable .o is not wired yet
  (bug-esp-emit-obj-proc-fixup-non-iram). esp_timer callbacks run in task
  context and do not need IRAM; drop the marker when that ticket lands.

  Expected qemu output:
    PXX timer: started
    PXX timer: tick=1
    ...
    PXX timer: tick=5
    PXX timer: done ticks=5 status=0 }

uses esptimer;

procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure vTaskDelay(ticks: Integer); external;

var
  ticks: Integer;

procedure OnTick(arg: Pointer); iram;   { iram; = interim, see header }
begin
  ticks := ticks + 1;
  esp_rom_printf('PXX timer: tick=%d'#10, ticks);
end;

var
  t: TEspTimer;
  waited, status: Integer;
begin
  ticks := 0;
  status := 0;

  TimerInit(t);
  t.OnElapsed := @OnTick;
  if not TimerStartPeriodicMs(t, 100) then
    status := 1
  else
    esp_rom_printf('PXX timer: started'#10, 0);

  { wait (yielding) for 5 ticks, bounded so a dead timer still reports }
  waited := 0;
  while (ticks < 5) and (waited < 100) do
  begin
    vTaskDelay(10);   { 10 ticks @ default 100Hz = 100ms per loop }
    waited := waited + 1;
  end;
  if ticks < 5 then status := status or 2;

  if not TimerStop(t) then status := status or 4;
  TimerDone(t);

  esp_rom_printf('PXX timer: done ticks=%d', ticks);
  esp_rom_printf(' status=%d'#10, status);

  { park politely so the FreeRTOS idle task keeps feeding the WDT }
  while True do
    vTaskDelay(1000);
end.

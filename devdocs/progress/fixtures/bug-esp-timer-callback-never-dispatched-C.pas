program tfire;
{ Does a 64-bit argument after ONE pointer argument reach a gcc-built callee?
  Variant A passes it as declared; variant B inserts a dummy word so the pair
  lands on an EVEN register, which is where the RISC-V ILP32 / Xtensa ABIs put
  a 64-bit scalar. If only B fires, pxx is not aligning the pair. }
procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure vTaskDelay(ticks: Integer); external;
function esp_timer_create(args: Pointer; outHandle: Pointer): Integer; external;
function esp_timer_start_periodic(handle: Pointer; periodUs: Int64): Integer; external;

function esp_timer_stop(handle: Pointer): Integer; external;

type
  TArgs = record
    callback: Pointer; arg: Pointer; dispatch_method: Integer;
    name: Pointer; skip_unhandled: Byte; p0, p1, p2: Byte;
  end;

var
  ticks: Integer;
  nm: array[0..3] of Char = ('p', 'x', 'x', #0);

procedure OnTick(arg: Pointer);
begin
  ticks := ticks + 1;
end;

function MakeTimer: Pointer;
var a: TArgs; h: Pointer; rc: Integer;
begin
  a.callback := @OnTick; a.arg := nil; a.dispatch_method := 0;
  a.name := @nm[0]; a.skip_unhandled := 0; a.p0 := 0; a.p1 := 0; a.p2 := 0;
  h := nil;
  rc := esp_timer_create(@a, @h);
  esp_rom_printf('create rc=%d'#10, rc);
  MakeTimer := h;
end;

var h: Pointer; rc, i: Integer;
begin
  ticks := 0;
  h := MakeTimer;
  esp_rom_printf('cb=%x'#10, Integer(@OnTick));
  rc := esp_timer_start_periodic(h, 100000);
  esp_rom_printf('A start rc=%d'#10, rc);
  i := 0; while i < 30 do begin vTaskDelay(10); i := i + 1; end;
  esp_rom_printf('A ticks=%d'#10, ticks);
  rc := esp_timer_stop(h);

  while True do vTaskDelay(1000);
end.

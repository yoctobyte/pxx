program test_esp_hw_validation;
{ The program to run FIRST on a real ESP32 board (feature-esp-hardware-flash-
  validation). It is deliberately boring: everything it prints is pure
  computation, so the board's UART output must be byte-identical to the same
  source run on x86-64 — `tools/esp_flash.sh` does that diff for you.

    tools/esp_flash.sh --chip esp32s3 test/test_esp_hw_validation.pas

  What it covers, in the order a wrong answer would tell you the most:
    - 64-bit arithmetic (the soft-float/Int64 kernels)
    - a by-value record result and >6-word argument lists (the xtensa ABI work
      of 2026-08-02 — these are the paths a windowed build gets wrong first)
    - managed strings on the SDK heap
    - a GPIO write per line, so a scope or an LED shows the program is really
      executing and not being replayed from a stale image

  It does NOT test interrupts: the esp_timer callback surface is broken today
  (bug-esp-timer-callback-never-dispatched), and examples/esp32/timer-s3 is the
  place to retest that once it is fixed. }

{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}
{$ifdef CPU_RISCV32}{$define PXX_ESP}{$endif}

{$ifdef PXX_ESP_BARE}
procedure PutC(code: Integer);
begin
  PByte(Int64($60000000))^ := Byte(code);
end;
procedure LedInit; begin end;
procedure LedSet(level: Integer); begin end;
procedure Park; begin while True do ; end;
{$else}
{$ifdef PXX_ESP}
procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure gpio_set_direction(gpio_num: Integer; mode: Integer); external;
procedure gpio_set_level(gpio_num: Integer; level: Integer); external;
procedure vTaskDelay(ticks: Integer); external;
const LED_GPIO = 2;   { the devkit LED on most S2/S3/C3 boards; harmless if not }
procedure PutC(code: Integer);
begin
  esp_rom_printf('%c', code);
end;
procedure LedInit;
begin
  gpio_set_direction(LED_GPIO, 2);   { GPIO_MODE_OUTPUT }
end;
procedure LedSet(level: Integer);
begin
  gpio_set_level(LED_GPIO, level);
end;
{ Park by YIELDING. A bare `while True do ;` starves the FreeRTOS idle task and
  the task watchdog resets the board a few seconds later — which looks exactly
  like a crash if you do not know to expect it. }
procedure Park;
begin
  while True do vTaskDelay(100);
end;
{$else}
procedure PutC(code: Integer);
var b: Byte; r: Int64;
begin
  b := code;
  r := __pxxrawsyscall(1, 1, Int64(@b), 1);
end;
procedure LedInit; begin end;
procedure LedSet(level: Integer); begin end;
procedure Park; begin end;
{$endif}
{$endif}

procedure PutS(const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do PutC(Ord(s[i]));
end;

procedure PutIntRec(n: Int64);
begin
  if n >= 10 then PutIntRec(n div 10);
  PutC(48 + Integer(n mod 10));
end;

procedure PutInt(n: Int64);
begin
  if n < 0 then begin PutC(45); n := -n; end;
  PutIntRec(n);
end;

type
  TVec = record x, y, z: Int64; end;

{ 9 argument words, and on windowed a hidden result pointer takes word 0 —
  so this one call exercises both halves of the xtensa ABI work. }
function MakeVec(a, b, c, d, e, f, g, h, i: Integer): TVec;
begin
  MakeVec.x := Int64(a) * 1000000 + b;
  MakeVec.y := Int64(c) * d * e;
  MakeVec.z := Int64(f) + g + h + i;
end;

var
  v: TVec;
  q: Int64;
  s: AnsiString;
  i: Integer;
begin
  LedInit;

  LedSet(1);
  PutS('pxx esp hw validation'); PutC(10);

  q := 1;
  for i := 1 to 20 do q := q * 3;
  LedSet(0);
  PutS('pow3^20 '); PutInt(q); PutC(10);

  q := -9223372036854775807;
  LedSet(1);
  PutS('int64min+1 '); PutInt(q); PutC(10);
  PutS('divmod '); PutInt(q div 1000003); PutC(32); PutInt(q mod 1000003); PutC(10);

  v := MakeVec(7, 11, 13, 17, 19, 23, 29, 31, 37);
  LedSet(0);
  PutS('vec '); PutInt(v.x); PutC(32); PutInt(v.y); PutC(32); PutInt(v.z); PutC(10);

  s := '';
  for i := 1 to 8 do s := s + Chr(64 + i);
  LedSet(1);
  PutS('string '); PutS(s); PutC(32); PutInt(Length(s)); PutC(10);

  PutS('ok'); PutC(10);
  Park;
end.

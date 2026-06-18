program test_esp_bare;
{ Bare-metal ESP32-C3 boot (feature-esp32-bare-boot): no ESP-IDF. The image is
  linked at the SoC SRAM map and booted directly via `qemu-system-riscv32
  -M esp32c3 -kernel`. Output goes straight to the UART0 transmit FIFO (MMIO at
  0x60000000) from the program itself -- no esp_rom_printf, no FreeRTOS. The
  x86-64 oracle runs the same source over a write(2) syscall, so the serial
  bytes must match byte-for-byte. Exercises the static-arena heap + managed
  AnsiString on bare metal too (PutS takes a const AnsiString). }

{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}
{$ifdef CPU_RISCV32}{$define PXX_ESP}{$endif}

{$ifdef PXX_ESP_BARE}
{ Bare metal: byte -> UART0 TX FIFO. qemu drains it instantly. }
procedure PutC(code: Integer);
begin
  PByte(Int64($60000000))^ := Byte(code);
end;
{$else}
{$ifdef PXX_ESP}
procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure PutC(code: Integer);
begin
  esp_rom_printf('%c', code);
end;
{$else}
procedure PutC(code: Integer);
var b: Byte; r: Int64;
begin
  b := code;
  r := __pxxrawsyscall(1, 1, Int64(@b), 1);
end;
{$endif}
{$endif}

procedure PutS(const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do PutC(Ord(s[i]));
end;

procedure PutIntRec(n: Integer);
begin
  if n >= 10 then PutIntRec(n div 10);
  PutC(48 + n mod 10);
end;

procedure PutInt(n: Integer);
begin
  if n < 0 then begin PutC(45); n := -n; end;
  PutIntRec(n);
end;

begin
  PutS('hello esp32 bare');
  PutC(10);
  PutInt(12345); PutC(10);
  PutInt(-42); PutC(10);
{$ifdef PXX_ESP} while True do ; {$endif}
end.

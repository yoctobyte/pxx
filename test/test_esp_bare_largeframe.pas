program test_esp_bare_largeframe;
{ Bare-metal Call0 large-frame regression (bug-xtensa-call0-large-frame-truncates).
  BigSum has a ~256-byte local array, so its frame exceeds ADDI's +-128 reach.
  Before the fix the Call0 prologue lowered sp with a single ADDI whose 8-bit
  immediate wrapped, corrupting the stack and the computed sum. The x86-64 oracle
  runs the same source, so the UART bytes must match byte-for-byte. }

{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}
{$ifdef CPU_RISCV32}{$define PXX_ESP}{$endif}

{$ifdef PXX_ESP_BARE}
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

{ Large local frame: 64 Integers = 256 bytes, beyond ADDI's +-128. }
function BigSum: Integer;
var a: array[0..63] of Integer;
    i, s: Integer;
begin
  for i := 0 to 63 do a[i] := i * 2 + 1;
  s := 0;
  for i := 0 to 63 do s := s + a[i];
  BigSum := s;
end;

begin
  PutInt(BigSum); PutC(10);   { 64*64 = 4096 }
{$ifdef PXX_ESP} while True do ; {$endif}
end.

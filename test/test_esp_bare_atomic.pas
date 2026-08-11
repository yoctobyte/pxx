program test_esp_bare_atomic;
{ Bare-metal ATOMICS on both ESP families, booted under the Espressif qemu and
  diffed against the x86-64 oracle running the same source
  (bug-a-riscv32-and-xtensa-have-no-atomic-codegen).

  This is the only way to verify these: the primitives are hand-encoded, and
  hosted xtensa cannot even link WriteLn ("external (dynamic) symbols not yet
  supported"), so a compile is not evidence. The instruction ENCODINGS were
  taken from xtensa-esp32s3-elf-as / riscv32-esp-elf-as rather than from the
  manuals, and this test is what proves the SEQUENCES around them.

  esp32s3 (xtensa) uses S32C1I, the hardware compare-and-swap on every LX6/LX7.
  esp32c3 (riscv32) has NO atomic ISA — RV32IMC, no `A` extension — so it masks
  interrupts around the read-modify-write, which is correct because that part is
  single-core (SocCoreCount = 1). The capability table is what routes each.

  The PutC/PutS/PutInt scaffolding is test_esp_bare.pas's, unchanged. }

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

uses palatomic;

var n, r: LongInt;

begin
  n := 10;
  r := InterLockedIncrement(n);
  PutS('inc '); PutInt(r); PutC(32); PutInt(n); PutC(10);

  r := InterLockedDecrement(n);
  PutS('dec '); PutInt(r); PutC(32); PutInt(n); PutC(10);

  r := InterLockedExchange(n, 42);
  PutS('xchg '); PutInt(r); PutC(32); PutInt(n); PutC(10);

  r := InterLockedExchangeAdd(n, 5);
  PutS('add '); PutInt(r); PutC(32); PutInt(n); PutC(10);

  { CAS that MATCHES: swaps, and answers the old value }
  r := InterLockedCompareExchange(n, 99, 47);
  PutS('cas-hit '); PutInt(r); PutC(32); PutInt(n); PutC(10);

  { CAS that MISSES: must leave the value alone }
  r := InterLockedCompareExchange(n, 7, 1234);
  PutS('cas-miss '); PutInt(r); PutC(32); PutInt(n); PutC(10);
{$ifdef PXX_ESP} while True do ; {$endif}
end.

program test_esp_stack_args;
{ Calls and definitions with MORE THAN 6 parameter words on xtensa
  (feature-xtensa-stack-args-over-6-words). Words 0..5 travel in the register
  set (a2..a7 Call0 / a10..a15 windowed); everything beyond goes in the
  caller's outgoing stack area at sp+0 and is read back by the callee -- the
  same layout xtensa gcc uses, so the ABI stays crossable in both directions.

  Runs three ways off one source, all producing identical bytes:
    x86-64          the oracle (write(2))
    --esp-profile=bare   Call0, UART MMIO   (tools/esp_run_bare.sh)
    --platform=esp       windowed via IDF   (tools/esp_run.sh) }

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

{ 7 words: the shape that blocks the ESP PAL (PalBackendVforkAndExec). }
function Sum7(a, b, c, d, e, f, g: Integer): Integer;
begin
  Sum7 := a + b * 10 + c * 100 + d * 1000 + e * 10000 + f * 100000 + g * 1000000;
end;

{ 9 words -- three on the stack, the measured gcc reference case. }
function Sum9(a, b, c, d, e, f, g, h, i: Integer): Integer;
begin
  Sum9 := a + b * 2 + c * 3 + d * 4 + e * 5 + f * 6 + g * 7 + h * 8 + i * 9;
end;

{ 12 words, and the overflow args are read in a non-linear order so a slot
  mix-up cannot cancel out. }
function Pick12(a, b, c, d, e, f, g, h, i, j, k, l: Integer): Integer;
begin
  Pick12 := l * 1000 + g * 100 + k * 10 + h - i - j - a - b - c - d - e - f;
end;

{ A var parameter costs one word (it passes an address) and may itself land in
  an overflow slot: the callee has to load the pointer from the stack and then
  write through it. }
procedure Bump10(a, b, c, d, e, f, g, h, i: Integer; var outv: Integer);
begin
  outv := a + b + c + d + e + f + g + h + i;
end;

{ Mixed widths: an Int64 by value is two words, so the pair straddles the
  register/stack boundary (words 4..5 in registers, 6..7 on the stack). }
function Mix(a, b, c, d: Integer; p, q: Int64; r: Integer): Int64;
begin
  Mix := Int64(a) + b * 2 + c * 3 + d * 4 + p * 5 + q * 6 + r * 7;
end;

{ Overflow args must survive a nested call that itself spills: the inner call
  reuses the same outgoing area, so the outer one must have finished with it. }
function Nested(a, b, c, d, e, f, g, h: Integer): Integer;
begin
  Nested := Sum9(a, b, c, d, e, f, g, h, 9) + Sum7(a, b, c, d, e, f, g);
end;

{ A by-value record result rides on the same machinery: on windowed the hidden
  destination pointer is argument word 0, so eight declared arguments become
  nine words and the last three spill. }
type
  TBig = record a, b, c, d, e: Integer; end;

function MakeBig(p1, p2, p3, p4, p5, p6, p7, p8: Integer): TBig;
begin
  MakeBig.a := p1 + p8;
  MakeBig.b := p2 * p7;
  MakeBig.c := p3 - p6;
  MakeBig.d := p4 + p5;
  MakeBig.e := p1 + p2 + p3 + p4 + p5 + p6 + p7 + p8;
end;

var
  n: Integer;
  m: Int64;
  big: TBig;
begin
  PutS('sum7 ');  PutInt(Sum7(1, 2, 3, 4, 5, 6, 7)); PutC(10);
  PutS('sum9 ');  PutInt(Sum9(1, 2, 3, 4, 5, 6, 7, 8, 9)); PutC(10);
  PutS('pick12 ');
  PutInt(Pick12(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)); PutC(10);
  n := 0;
  Bump10(1, 2, 3, 4, 5, 6, 7, 8, 9, n);
  PutS('bump10 '); PutInt(n); PutC(10);
  m := Mix(1, 2, 3, 4, 5, 6, 7);
  PutS('mix '); PutInt(Integer(m)); PutC(10);
  PutS('nested '); PutInt(Nested(1, 2, 3, 4, 5, 6, 7, 8)); PutC(10);
  big := MakeBig(1, 2, 3, 4, 5, 6, 7, 8);
  PutS('big ');
  PutInt(big.a); PutC(32); PutInt(big.b); PutC(32); PutInt(big.c); PutC(32);
  PutInt(big.d); PutC(32); PutInt(big.e); PutC(10);
{$ifdef PXX_ESP} while True do ; {$endif}
end.

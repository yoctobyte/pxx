program test_esp_bare_asm;
{ Inline `asm ... end` on xtensa (feature-inline-asm-xtensa) — the last leg of
  the multi-arch rollout, and the same three things its riscv32/aarch64/arm32/
  i386 siblings prove: a local/param as an operand, labels + branches, and a
  global reached by materializing its address.

  Xtensa is the one target that cannot substitute a frame reference INTO an
  operand: l32i/s32i encode their offset as an UNSIGNED imm8*4 (0..1020) while
  frame offsets are negative, so there is no `<off>(fp)` form. `l32i a4, n`
  therefore lowers to "materialize the address into a8, then load at offset 0",
  which is why a8 is reserved here and why the frame pointer (a15 under Call0,
  a7 under windowed) never appears in the source.

  Bare-metal, because that is what runs on the hardware this target exists for:
  the x86-64 oracle computes the same three numbers in plain Pascal, and the
  UART bytes must match it byte for byte. }

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

var
  g: Integer;

{ params and a local as operands }
function AddViaAsm(a, b: Integer): Integer;
var r: Integer;
begin
  r := 0;
{$ifdef CPU_XTENSA}
  asm
    l32i a4, a
    l32i a5, b
    add a6, a4, a5
    s32i a6, r
  end;
{$else}
  r := a + b;
{$endif}
  AddViaAsm := r;
end;

{ labels, a backward jump and a conditional branch. Xtensa has no zero
  register, so the loop's sentinel is materialized into a6. }
function SumLoop(n: Integer): Integer;
var r: Integer;
begin
  r := 0;
{$ifdef CPU_XTENSA}
  asm
    l32i a4, n
    movi a5, 0
    movi a6, 0
  loop:
    beq a4, a6, done
    add a5, a5, a4
    addi a4, a4, -1
    j loop
  done:
    s32i a5, r
  end;
{$else}
  while n > 0 do begin r := r + n; n := n - 1; end;
{$endif}
  SumLoop := r;
end;

{ a global, through `la` — the L32R literal + R_XTENSA_32 relocation path }
procedure BumpGlobal;
begin
{$ifdef CPU_XTENSA}
  asm
    la a4, g
    l32i a5, a4, 0
    addi a5, a5, 5
    s32i a5, a4, 0
  end;
{$else}
  g := g + 5;
{$endif}
end;

{ a global as a load/store operand directly — the @glob arm of the same
  address materialization, without the explicit `la` }
function ReadGlobalViaAsm: Integer;
var r: Integer;
begin
  r := 0;
{$ifdef CPU_XTENSA}
  asm
    l32i a4, g
    addi a4, a4, 1
    s32i a4, r
  end;
{$else}
  r := g + 1;
{$endif}
  ReadGlobalViaAsm := r;
end;

{ A frame big enough that the local's offset is past ADDI's +-128: the address
  materialization must fall back to the literal pool, exactly as the backend's
  own EmitFrameAddrXtensa does (it IS the backend's, which is the point — the
  engine calls it rather than open-coding a second copy). }
function FarLocal: Integer;
var pad: array[0..255] of Integer;
    r, i: Integer;
begin
  for i := 0 to 255 do pad[i] := i;
  r := 0;
{$ifdef CPU_XTENSA}
  asm
    movi a4, 7
    s32i a4, r
    l32i a5, r
    addi a5, a5, 1
    s32i a5, r
  end;
{$else}
  r := 8;
{$endif}
  FarLocal := r + pad[255];
end;

begin
  PutInt(AddViaAsm(19, 23)); PutC(10);   { 42 }
  PutInt(SumLoop(10)); PutC(10);         { 55 }
  g := 37;
  BumpGlobal;
  PutInt(g); PutC(10);                   { 42 }
  PutInt(ReadGlobalViaAsm); PutC(10);    { 43 }
  PutInt(FarLocal); PutC(10);            { 8 + 255 = 263 }
{$ifdef PXX_ESP} while True do ; {$endif}
end.

program test_esp_bare_variant;
{ VARIANTS on the bare ESP profile — the oracle half of the variant split, and
  deliberately written BEFORE the split so it can say whether a split that
  compiles also still computes.

  builtinheap.pas:5701..6992 is ONE `{$ifndef PXX_ESP}` span of 1292 lines that
  holds the variant runtime AND the whole float FORMATTING family, so bare gets
  neither. Measured 2026-09-20, nine of the twelve variant routines are
  float-free and three are genuinely coupled — `PXXVarBinOp` (a double arm that
  is unconditional code, not a droppable branch), `PXXVarNot`, `PXXWriteVariant`.
  feature-a-one-guard-excludes-both-the-unimplementable-and-the-merely-adjacent

  WHY A VALUE FIXTURE AND NOT A COMPILE ROW: a split is a change to which
  bodies exist, and the failure it can produce is a variant that builds and
  then reads the wrong half of its payload — a tag/value mismatch prints
  something, it does not crash. A compile-only row cannot tell that from a
  pass, and `assert_no_leak`-style checks cannot either, because the bytes are
  all accounted for. So every arm here PRINTS what it computed and the serial
  output is compared byte-for-byte against the same source run on x86-64.

  DELIBERATELY FLOAT-FREE, and that is the point rather than a convenience: the
  open question is whether a bare program touching an INTEGER or STRING variant
  must pay softfloat (~54-64 KB) for `PXXVarBinOp`'s double arm. This fixture
  is the program that question is about, so putting a float variant in it would
  destroy the measurement it exists to make possible.

  Same PutC/PutS scaffolding as test_esp_bare.pas and test_esp_bare_managed.pas:
  UART0 MMIO on bare, esp_rom_printf on IDF, a raw write syscall on the oracle. }

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

{ Our own integer formatter, on purpose: writing a variant through the RTL
  would route via PXXWriteVariant, which calls PXXWriteFloatNat and is one of
  the three genuinely float-coupled routines. Using it here would make the
  fixture require the thing it is meant to measure the absence of. }
procedure PutI(v: Int64);
var buf: array[0..23] of Byte; n: Integer; neg: Boolean;
begin
  n := 0;
  neg := v < 0;
  if neg then v := -v;
  if v = 0 then begin buf[n] := 48; n := n + 1; end;
  while v > 0 do
  begin
    buf[n] := 48 + Byte(v mod 10);
    v := v div 10;
    n := n + 1;
  end;
  if neg then PutC(45);
  while n > 0 do
  begin
    n := n - 1;
    PutC(buf[n]);
  end;
end;

{ Integer arithmetic through PXXVarBinOp's INTEGER arm — the ordinary use, and
  the one that decides whether an integer variant can be free of softfloat. }
procedure VarIntArith;
var a, b, r: Variant;
begin
  a := 6;
  b := 7;
  r := a * b;
  PutS('arith:'); PutI(r); PutC(10);
end;

{ VarOpIsBitwise / VarBitwiseInt — a separate dispatch inside PXXVarBinOp, and
  both of those helpers are float-free, so this arm is the one most likely to
  survive a split intact. Three operators rather than one: a bitwise dispatch
  that falls through to arithmetic gives a WRONG NUMBER, not an error. }
procedure VarBitwise;
var a, b: Variant;
begin
  a := 12;
  b := 10;
  PutS('bits:');
  PutI(a and b); PutC(58);
  PutI(a or b);  PutC(58);
  PutI(a xor b); PutC(10);
end;

{ PXXVarStrAppend, and the payload release behind it. Appending twice matters:
  the first append allocates, the second must release the intermediate, and a
  missing release here is invisible to a value check on the RESULT alone -- so
  the old value is read back afterwards through a second variant that still
  holds it. }
procedure VarStrAppend;
var a, keep: Variant;
  s: AnsiString;
begin
  a := 'ab';
  keep := a;
  a := a + 'cd';
  a := a + 'ef';
  s := a;
  PutS('str:'); PutS(s);
  s := keep;
  PutC(58); PutS(s); PutC(10);
end;

{ Comparison — PXXVarBinOp with isCompare set, which returns through a
  different path than arithmetic and is where an integer/float tag confusion
  shows up as a plausible wrong answer rather than a fault. Both directions,
  because a comparator stuck at one value passes half the rows. }
procedure VarCompare;
var a, b: Variant;
  eq, lt: Integer;
begin
  a := 5;
  b := 5;
  eq := 0;
  if a = b then eq := 1;
  b := 9;
  lt := 0;
  if a < b then lt := 1;
  PutS('cmp:'); PutI(eq); PutC(58); PutI(lt); PutC(10);
end;

{ PXXVarRetain / PXXVarReleasePayload: copy a string variant, then overwrite
  the ORIGINAL with an integer so its payload is released, then read the copy.
  If the copy did not retain, this reads freed memory; the read AFTER the
  overwrite is the whole assertion.

  Overwriting rather than calling `VarClear` ON PURPOSE. VarClear lives in
  lib/rtl/variants.pas and would make this fixture need `uses variants`, which
  drags a unit into the one program whose whole job is to measure what a bare
  variant program costs. The overwrite reaches PXXVarReleasePayload by the
  route an ordinary program takes anyway. }
procedure VarCopyClear;
var a, b: Variant;
  s: AnsiString;
begin
  a := 'payload';
  b := a;
  a := 0;
  s := b;
  PutS('copy:'); PutS(s); PutC(58); PutI(a); PutC(10);
end;

begin
  VarIntArith;
  VarBitwise;
  VarStrAppend;
  VarCompare;
  VarCopyClear;
  PutS('variant ok'); PutC(10);
{$ifdef PXX_ESP} while True do ; {$endif}
end.

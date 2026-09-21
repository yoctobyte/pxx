program test_esp_bare_sr;
{ Bare-metal XTENSA special-register access (wsr/rsr with a numeric SR),
  booted under the Espressif qemu and diffed against the x86-64 oracle
  (feature-s-the-xtensa-raw-isr-install-has-no-vecbase-write-and-no-isr-stack).

  The xtensa sibling of test_esp_bare_csr.pas, and deliberately a SMALLER
  claim than that one. It proves the capability -- an arbitrary special
  register can be written and read back from Pascal inline asm -- and it does
  NOT install a vector, because on xtensa that is not a matter of writing one
  register.

  WHY NOT, MEASURED FROM ESP-IDF'S OWN LINKER SCRIPT RATHER THAN REMEMBERED
  (components/esp_system/ld/esp32s3/sections.ld.in): VECBASE points at a
  TABLE, not at a handler, with each vector at a fixed offset from the base --
  0x180 Level2, 0x1c0 Level3, 0x200 Level4, 0x240 Level5, 0x280 Debug, 0x2c0
  NMI, 0x300 KernelException, 0x340 UserException, 0x3C0 DoubleException. So a
  raw install needs an aligned table with stub code at the right offset, and a
  level-1 interrupt does not even get its own slot: it arrives at the USER
  exception vector with EXCCAUSE = 4 and must be dispatched. riscv32's mtvec
  is a single handler address and needed none of that.

  EXCSAVE_1 ($D1) is the register under test because it is architecturally a
  scratch register -- the hardware never reads it, so clobbering it on bare
  cannot disturb anything, and it is the register an eventual vector stub will
  itself need in order to free up an AR. VECBASE is deliberately NOT written
  here: doing so with no table behind it would point the core at whatever
  happens to be at that address.

  The value 1445 is chosen to fit MOVI's 12-bit signed immediate so the test
  does not silently depend on literal-pool expansion, and to be neither 0 nor
  a width -- a register that was never written reads back as something else. }

procedure PutC(code: Integer);
begin
{$ifdef PXX_ESP_BARE}
  PByte(Int64($60000000))^ := Byte(code);
{$else}
  Write(Chr(code));
{$endif}
end;

procedure PutS(const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do PutC(Ord(s[i]));
end;

procedure PutInt(n: Integer);
begin
  if n < 0 then begin PutC(45); n := -n; end;
  if n >= 10 then PutInt(n div 10);
  PutC(48 + n mod 10);
end;

var
  srOut: Integer;

begin
  srOut := 0;

{$ifdef CPU_XTENSA}
  asm
    movi a4, 1445
    wsr  a4, $d1        { EXCSAVE_1 := 1445 }
    movi a5, 0          { prove the read is what produces the value }
    rsr  a5, $d1
    la   a6, srOut
    s32i a5, a6, 0
  end;
{$else}
  { x86-64 oracle: no special registers. Prints what a correct bare run prints. }
  srOut := 1445;
{$endif}

  PutS('excsave1 readback '); PutInt(srOut); PutC(10);
  if srOut = 1445 then PutS('SR-OK') else PutS('SR-FAIL');
  PutC(10);
end.

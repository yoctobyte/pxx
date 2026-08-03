program test_esp_bare_arg64;
{ 64-bit arguments at ODD word indices, on real ESP silicon under qemu.

  The xtensa C ABI starts a 64-bit argument at an EVEN word index; pxx's own
  convention used to pack words with no padding, so a routine called FROM C read
  such a parameter one register early (gcc puts f(int, long long)'s second
  argument in a4:a5, the pxx callee spill read a3:a4). The rule is now applied
  unconditionally on both sides — a calling convention is the target's by
  definition — which means the INTERNAL calls below moved too, and this is what
  proves they still agree. Every call site here puts the 64-bit value at an odd
  word index (one, three or five preceding words), including one that straddles
  the a2..a7 register set into the stack area.
  bug-a-pxx-callee-uses-internal-abi-for-64bit-params-called-from-c

  Same shape as test_esp_bare.pas: UART0 MMIO on bare metal, write(2) on the
  x86-64 oracle, and the serial bytes must match byte-for-byte. }

{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}
{$ifdef CPU_RISCV32}{$define PXX_ESP}{$endif}

{$ifdef PXX_ESP_BARE}
procedure PutC(code: Integer);
begin
  PByte(Int64($60000000))^ := Byte(code);
end;
{$else}
procedure PutC(code: Integer);
var b: Byte; r: Int64;
begin
  b := code;
  r := __pxxrawsyscall(1, 1, Int64(@b), 1);
end;
{$endif}

procedure PutS(const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do PutC(Ord(s[i]));
end;

procedure PutU64Rec(n: UInt64);
begin
  if n >= 10 then PutU64Rec(n div 10);
  PutC(48 + Integer(n mod 10));
end;

procedure PutU64(n: UInt64);
begin
  PutU64Rec(n);
  PutC(10);
end;

{ one preceding word -> the 64-bit value lands at word index 1 (odd) }
procedure Odd1(a: Integer; v: UInt64);
begin
  PutS('odd1 a='); PutU64(UInt64(a));
  PutS('odd1 v='); PutU64(v);
end;

{ three preceding words -> index 3 (odd) }
procedure Odd3(a, b, c: Integer; v: UInt64);
begin
  PutS('odd3 c='); PutU64(UInt64(c));
  PutS('odd3 v='); PutU64(v);
end;

{ five preceding words -> index 5 (odd): the pad pushes the pair past a7, so lo
  and hi both come from the caller's stack area }
procedure Odd5(a, b, c, d, e: Integer; v: UInt64);
begin
  PutS('odd5 e='); PutU64(UInt64(e));
  PutS('odd5 v='); PutU64(v);
end;

{ two preceding words -> index 2 (even): the no-pad path must be untouched }
procedure Even2(a, b: Integer; v: UInt64);
begin
  PutS('even2 b='); PutU64(UInt64(b));
  PutS('even2 v='); PutU64(v);
end;

begin
  Odd1(7, 1234567890123);
  Odd3(1, 2, 3, 9876543210987);
  Odd5(1, 2, 3, 4, 5, 1122334455667788);
  Even2(1, 42, 555666777888);
{$ifdef PXX_ESP} while True do ; {$endif}
end.

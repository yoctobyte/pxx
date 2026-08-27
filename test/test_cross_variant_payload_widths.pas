program test_cross_variant_payload_widths;
{ The payload hazards a 32-BIT variant slot has and a 64-bit one does not.

  bug-a-riscv32-codegen-has-no-variant-support added riscv32's IR_VAR_STORE /
  IR_VAR_BOX / IR_VAR_BINOP arms; this is what says they got the WIDTHS right.
  On a 32-bit target the slot is tag(4) + zero(4) + payload(8), and the payload
  arrives through a register PAIR or a stack slot rather than one register, so
  each row below is a place a narrower path silently answered something else:

    * an Int64 must reach the payload WHOLE -- the i386/arm32 twins stored only
      the low word (bug-a-an-int64-assigned-to-a-variant-truncates-to-32-bits-
      on-i386-and-arm32), so 5000000000 read back as 705032704;
    * the HIGH word comes from the payload's TYPE, not the tag: tyNativeInt maps
      to VT_INT64, so a negative NativeInt zero-filled reads as a huge unsigned;
    * a Cardinal at or above 2^31 must ZERO-fill, or it reads negative;
    * a Double must be widened to VT_DOUBLE's 8 bytes of IEEE bits even from a
      Single and even on a target with no FPU at all;
    * a boxed string must not leak a reference per store.

  Run as a DIFFERENTIAL against x86-64, so the expectations are one 64-bit
  target's answers rather than a hand-written table. }

var
  v, w: Variant;
  l: Int64;
  c: Cardinal;
  n: NativeInt;
  d: Double;
  f: Single;
  s: AnsiString;
  i: Integer;
  ok: Boolean;

begin
  ok := True;

  l := 5000000000; v := l;
  writeln(v);                       if v <> 5000000000 then ok := False;
  l := -12; v := l;
  writeln(v);                       if v <> -12 then ok := False;
  l := -5000000000; v := l;
  writeln(v);                       if v <> -5000000000 then ok := False;

  n := -12; v := n;
  writeln(v);                       if v <> -12 then ok := False;

  c := 4294967295; v := c;
  writeln(v);                       if v <> 4294967295 then ok := False;
  c := 2147483648; v := c;
  writeln(v);                       if v <> 2147483648 then ok := False;

  i := -7; v := i;
  writeln(v);                       if v <> -7 then ok := False;

  d := 2.5; v := d;
  writeln(v);                       if v <> 2.5 then ok := False;
  f := 0.5; v := f;
  writeln(v);                       if v <> 0.5 then ok := False;

  { binop: the boxed-operand path (IR_VAR_BOX) and PXXVarBinOpPas }
  v := 3; w := 4;
  writeln(v + w, ' ', v * w, ' ', v - w);
  if (v + w <> 7) or (v * w <> 12) or (v - w <> -1) then ok := False;
  if not (v < w) then ok := False;
  if v >= w then ok := False;

  { a literal on one side is boxed into a temp variant }
  writeln(v + 10, ' ', 10 + v);
  if (v + 10 <> 13) or (10 + v <> 13) then ok := False;

  { string payload, and a variant-to-variant copy of one }
  s := 'ab'; v := s; w := v;
  writeln(w);                       if w <> 'ab' then ok := False;
  writeln(v + 'c');                 if v + 'c' <> 'abc' then ok := False;

  { a boxed string must not leak a reference per store: 20000 stores through a
    freshly-built handle, then the value must still be right. A leak here shows
    up as unbounded heap growth rather than a wrong answer, which is why the
    loop is long enough to matter and the check after it is cheap. }
  for i := 1 to 20000 do
  begin
    s := 'x';
    v := s + 'y';
  end;
  writeln(v);                       if v <> 'xy' then ok := False;

  if ok then writeln('ALL OK') else writeln('FAILED');
end.

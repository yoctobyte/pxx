program test_const64;
{ bug-64bit-named-const-truncated-32bit-targets: a named constant was always
  declared tyInteger regardless of magnitude. The VALUE survived (ConstVal is an
  Int64), but the 32-bit backends materialized only the low word and
  sign-extended it, so `const K = UInt64($FFFFFFFF00000001)` loaded as 1 on
  i386/arm32/riscv32 while being correct on x86-64/aarch64 -- where every
  register is 64 bits wide, so the truncation could not show.

  Run this CROSS. On x86-64 alone it proves nothing. }

const
  K_ALLONES = UInt64($FFFFFFFFFFFFFFFF);  { -1: right even when truncated -- the coincidence that hid this }
  K_LOW32   = UInt64($00000000FFFFFFFF);  { needs bit 32..: truncation sign-extends to all-ones }
  K_HIGH    = UInt64($FFFFFFFF00000001);  { truncation keeps only the 1 }
  K_MID     = UInt64($00000004FFFFFFFD);  { truncation sign-extends to -3 }
  K_SMALL   = 42;                         { must STAY a plain Integer }
  K_NEG     = -7;
  K_INT_MAX = 2147483647;                 { boundary: still fits Integer }
  K_OVER    = 2147483648;                 { boundary: one past -- must widen }

var
  fails: Integer;
  u: UInt64;
  i: Integer;

procedure Chk(got, want: UInt64; const what: AnsiString);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want ', want);
    Inc(fails);
  end;
end;

begin
  fails := 0;

  u := K_ALLONES; Chk(u, UInt64($FFFFFFFFFFFFFFFF), 'all-ones');
  u := K_LOW32;   Chk(u, UInt64($00000000FFFFFFFF), 'low 32 bits set');
  u := K_HIGH;    Chk(u, UInt64($FFFFFFFF00000001), 'high word set');
  u := K_MID;     Chk(u, UInt64($00000004FFFFFFFD), 'straddles bit 32');
  u := K_OVER;    Chk(u, UInt64(2147483648), 'one past Integer max');

  { small constants must be unaffected -- they stay tyInteger }
  i := K_SMALL;   if i <> 42 then begin WriteLn('FAIL small'); Inc(fails); end;
  i := K_NEG;     if i <> -7 then begin WriteLn('FAIL negative'); Inc(fails); end;
  i := K_INT_MAX; if i <> 2147483647 then begin WriteLn('FAIL Integer max'); Inc(fails); end;

  { constants must survive arithmetic, not just assignment }
  u := K_HIGH + UInt64(1);
  Chk(u, UInt64($FFFFFFFF00000002), 'high word + 1');
  u := K_LOW32 shr 16;
  Chk(u, UInt64($FFFF), 'shift of a wide const');

  if fails = 0 then WriteLn('CONST64 OK')
  else WriteLn('CONST64 FAIL (', fails, ')');
end.

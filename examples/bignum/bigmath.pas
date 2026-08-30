{ SPDX-License-Identifier: 0BSD }
program BigMath;
{ Deterministic oracle for the bignum DivMod / ModPow / signed-arithmetic lane.

  Both compiler bugs this program was once shaped around are FIXED --
  bug-proc-local-managed-record-uninit (proc-local managed records not
  zero-initialised on entry, which is why all work is in the main body) and
  bug-nested-managed-return-call-arg (a managed-return call passed straight as
  an argument). Verified by re-running their own repros on x86-64, i386, arm32,
  riscv32 and aarch64, not by their ticket folders.

  The code is left as it stands, and that is a readability call rather than a
  constraint: in a checker like this one, `chk := BigAddSigned(prod, r); if
  BigCompare(chk, a) <> 0` names the intermediate that the FAIL message is
  about, and nesting it would read worse, not better. So these temps are
  ordinary style now. What was stale was this comment claiming otherwise.
  Helper procs are likewise available and simply not needed here.
  Integer-deterministic, so output is byte-identical across targets.
  Track B; pinned stable. }

uses bignum, sysutils;

var
  a, b, q, r, chk, prod, m, e, base, mp, sq: TBigInt;
  ok: Boolean;
begin
  ok := True;

  { --- DivMod invariant: q*b + r = a, FPC trunc-toward-zero signs --- }
  a := BigFromStr('123456789012345678901234567890');
  b := BigFromStr('9876543210');
  BigDivMod(a, b, q, r);
  prod := BigMul(q, b);
  chk := BigAddSigned(prod, r);
  writeln('a / b   q = ', BigToStr(q));
  writeln('a mod b r = ', BigToStr(r));
  if BigCompare(chk, a) <> 0 then begin ok := False; writeln('  FAIL: q*b+r <> a'); end;

  { negative dividend: -7 div 3 = -2, -7 mod 3 = -1 }
  a := BigFromInt(-7);
  b := BigFromInt(3);
  BigDivMod(a, b, q, r);
  writeln('-7 div 3 = ', BigToStr(q), '  (want -2)');
  writeln('-7 mod 3 = ', BigToStr(r), '  (want -1)');
  chk := BigFromInt(-2);
  if BigCompare(q, chk) <> 0 then begin ok := False; writeln('  FAIL: q'); end;
  chk := BigFromInt(-1);
  if BigCompare(r, chk) <> 0 then begin ok := False; writeln('  FAIL: r'); end;

  { |a| < |b|: quotient 0, remainder = a }
  a := BigFromInt(5);
  b := BigFromInt(1000000000000);
  BigDivMod(a, b, q, r);
  if (not BigIsZero(q)) or (BigCompare(r, a) <> 0) then
  begin ok := False; writeln('  FAIL: small/large'); end;

  { --- signed add / sub --- }
  a := BigFromStr('-100000000000000000000');
  b := BigFromStr('100000000000000000001');
  chk := BigAddSigned(a, b);
  writeln('a + b = ', BigToStr(chk), '  (want 1)');
  r := BigFromInt(1);
  if BigCompare(chk, r) <> 0 then begin ok := False; writeln('  FAIL: signed add'); end;
  chk := BigSubSigned(a, b);
  writeln('a - b = ', BigToStr(chk), '  (want -200000000000000000001)');
  r := BigFromStr('-200000000000000000001');
  if BigCompare(chk, r) <> 0 then begin ok := False; writeln('  FAIL: signed sub'); end;

  { --- ModPow known vectors --- }
  base := BigFromInt(4);  e := BigFromInt(13);  m := BigFromInt(497);
  mp := BigModPow(base, e, m);
  writeln('4^13 mod 497  = ', BigToStr(mp), '  (want 445)');
  chk := BigFromInt(445);
  if BigCompare(mp, chk) <> 0 then begin ok := False; writeln('  FAIL'); end;

  base := BigFromInt(2);  e := BigFromInt(10);  m := BigFromInt(1000);
  mp := BigModPow(base, e, m);
  writeln('2^10 mod 1000 = ', BigToStr(mp), '  (want 24)');
  chk := BigFromInt(24);
  if BigCompare(mp, chk) <> 0 then begin ok := False; writeln('  FAIL'); end;

  base := BigFromInt(3);  e := BigFromInt(5);  m := BigFromInt(7);
  mp := BigModPow(base, e, m);
  writeln('3^5 mod 7     = ', BigToStr(mp), '  (want 5)');
  chk := BigFromInt(5);
  if BigCompare(mp, chk) <> 0 then begin ok := False; writeln('  FAIL'); end;

  { big modulus self-consistency: (7^256) mod M == ((7^128 mod M)^2) mod M }
  m := BigFromStr('1000000000000000009');
  base := BigFromInt(7);
  e := BigFromInt(128);
  mp := BigModPow(base, e, m);
  e := BigFromInt(256);
  q := BigModPow(base, e, m);
  e := BigFromInt(2);
  sq := BigModPow(mp, e, m);
  writeln('7^256 mod M     = ', BigToStr(q));
  writeln('(7^128)^2 mod M = ', BigToStr(sq));
  if BigCompare(q, sq) <> 0 then begin ok := False; writeln('  FAIL: modpow square'); end;

  writeln;
  if ok then writeln('ALL OK') else writeln('FAILURES');
end.

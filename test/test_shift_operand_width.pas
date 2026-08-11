{ Shift WIDTH, after decide-shift-operator-promotion-width (user, 2026-08-10):
  a shift happens at NATIVE width and its result is not truncated back to the
  operand's declared width. Every row here used to assert FPC's operand-width
  answer and now asserts the native one — deliberately, and this file is the
  clearest statement of what that costs in FPC agreement:

    l shl n   (l: longint = 1, n = 31)   FPC -2147483648   pxx 2147483648
    l shr 9   (l = -2147483648)          FPC 4194304       pxx 36028797014769664
    l shl 1   (l = -2147483648)          FPC 0             pxx -4294967296

  In each case pxx keeps the bits FPC discards: the operand sign-extends to 64
  bits, the shift happens there, and nothing narrows the result afterwards.
  The unsigned row (c shl n) agrees, because 1 shl 31 fits either way.
  bug-a-shr-on-a-32-bit-operand-does-not-promote-like-fpc }
program shl32;
var l: longint; c: cardinal; n: longint;
begin
  l := 1; n := 31;
  writeln(int64(l shl n));         { 2147483648 }
  c := 1;
  writeln(int64(c shl n));         { 2147483648 — agrees with FPC }
  l := -2147483648;
  writeln(int64(l shr 9));         { 36028797014769664 }
  writeln(int64(l shl 1));         { -4294967296 }
end.

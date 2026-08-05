program test_interlocked_no_uses;
{ Regression: the InterLocked* family must resolve with NO `uses` line, the way
  FPC declares them (in the `system` unit). They existed only in
  lib/rtl/palatomic.pas, so real FPC source calling them did not compile as-is.

  Now also declared in compiler/builtin/builtin.pas — the system-unit analogue —
  with a token scan that pulls that unit when an InterLocked* call appears, the
  same mechanism Abs/Sqr/Delete/Insert already use. `uses palatomic` keeps
  working: a user RTL unit shadows a builtin of the same name, so both spellings
  resolve and neither is a duplicate definition (verified: 0 warnings).

  RETURN-VALUE CONTRACT, the part most likely to be got wrong:
  Increment/Decrement return the value AFTER the operation; Exchange /
  ExchangeAdd / CompareExchange return the value BEFORE it. The last two lines
  pin CompareExchange's swap AND its no-swap case, since the intrinsic takes
  (expected, new) while FPC takes (new, expected).
  Output verified byte-identical to FPC.
  bug-a-interlocked-family-needs-a-uses-clause-unlike-fpc }
var n: LongInt; q: Int64;
begin
  n := 5;
  writeln(InterLockedIncrement(n), ' ', n);          { 6 6 }
  writeln(InterLockedDecrement(n), ' ', n);          { 5 5 }
  writeln(InterLockedExchange(n, 42), ' ', n);       { 5 42 }
  writeln(InterLockedExchangeAdd(n, 8), ' ', n);     { 42 50 }
  writeln(InterLockedCompareExchange(n, 99, 50), ' ', n);  { 50 99 }
  writeln(InterLockedCompareExchange(n, 7, 50), ' ', n);   { 99 99 — no swap }
  q := 100;
  writeln(InterLockedIncrement64(q), ' ', q);        { 101 101 }
  writeln(InterLockedExchangeAdd64(q, 900), ' ', q); { 101 1001 }
  writeln('OK');
end.

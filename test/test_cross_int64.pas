program test_cross_int64;

{ ARM32 Int64 codegen: r0:r1 (lo:hi) register-pair model. Exercises 64-bit
  constants (incl. high-word-only), arithmetic, multiply, shifts, division,
  comparisons, and writeln, all of which must match the x86-64 oracle. The
  driving need is the lexer float-literal parser, which does manual 64-bit bit
  manipulation; before this, ARM32 truncated every Int64 op to 32 bits and the
  self-hosted compiler parsed all float literals to 0.0. }

var a, b, c: Int64;

begin
  { high-word-only constant (low 32 bits = 0) }
  a := $10000000000000;            { 2^52 }
  writeln('p52=', a);
  a := $8000000000000;            { 2^51 }
  writeln('p51=', a);

  { add / sub crossing the 32-bit boundary }
  a := 4000000000;                 { > 2^31 }
  b := 4000000000;
  writeln('add=', a + b);
  writeln('sub=', a - b);
  writeln('sub2=', b - 9000000000);

  { multiply needing full 64-bit }
  a := 1033;
  b := $10000000000000;
  writeln('mul=', a * b);
  a := 1000000000;
  b := 1000000;
  writeln('mul2=', a * b);

  { shifts by constant and by 32+ }
  a := 1;
  writeln('shl52=', a shl 52);
  a := 1033;
  writeln('shl52b=', a shl 52);
  a := $4652218415073722;
  writeln('shr1=', a shr 1);
  writeln('shr40=', a shr 40);

  { division and modulo }
  a := 4652218415073722368;
  writeln('div10=', a div 10);
  writeln('mod10=', a mod 10);
  a := -9000000000;
  writeln('sdiv=', a div 7);
  writeln('smod=', a mod 7);

  { comparisons across the boundary }
  a := 5000000000;
  b := 4000000000;
  if a > b then writeln('gt=ok') else writeln('gt=bad');
  if b < a then writeln('lt=ok') else writeln('lt=bad');
  if a <> b then writeln('ne=ok') else writeln('ne=bad');
  c := 5000000000;
  if a = c then writeln('eq=ok') else writeln('eq=bad');

  { bitwise }
  a := $FF00FF00FF00;
  b := $00FF00FF00FF;
  writeln('or=', a or b);
  writeln('and=', a and b);

  { Low(Int64) through the WRITER. The value survives everywhere; what broke
    was the rendering, and on one target only. aarch64's signed-integer writer
    ran the digit loop with sdiv AFTER negating, and `neg` of Low(Int64) is
    Low(Int64) again -- its magnitude does not fit a signed 64-bit register --
    so every remainder came out negative and every digit byte was Ord('0') - d:

      -'..--).0-*(+,))+(0(     instead of   -9223372036854775808

    All nineteen digits, so the arithmetic was right and only the character
    formed from each was wrong. Low+1 printed correctly, which is what made it
    look like an edge case rather than a sign bug.
    bug-a-aarch64-writeln-of-low-int64-prints-negated-digit-bytes }
  a := -9223372036854775807; a := a - 1;   { built at run time }
  writeln('rtlow=', a);
  b := Low(Int64);                          { and as a constant }
  writeln('lolow=', b);
  writeln('lohigh=', High(Int64));
  writeln('lowp1=', Low(Int64) + 1);
end.

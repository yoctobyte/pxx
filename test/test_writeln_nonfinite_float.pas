{ writeln/write/Str of a NON-FINITE Double — bug-a-writeln-of-a-non-finite-double-hangs.

  The scientific formatter normalises into [1,10) with `while v >= 10 do v := v / 10`.
  `Inf / 10` is still Inf, so that loop NEVER EXITS; a NaN compares UNORDERED, so it
  escapes the first loop only to spin in the second. writeln emitted its sign and then
  hung — the failure shape worse than a crash: no location, and it eats a suite timeout
  slot. Reachable from ordinary code, because a float divide by zero yields Inf BY
  DESIGN here rather than erroring (decide-int-div-zero-behavior-unification).

  FIVE formatters had to be guarded, and they disagreed about how to be wrong:
    - EmitWriteFloatSci   (x86-64 native)  — hung
    - EmitWriteFloatFixed (x86-64 native)  — did NOT hang; printed
                                             9223372036854775809.000000, silent debris
    - PXXWriteFloatSci    (portable)       — hung; this is why i386 still hung after
                                             x86-64 was fixed
    - PXXWriteFloatFixed  (portable)       — hung
    - FloatToExpStr / StrFloat (builtin)   — hung; FloatToStr beside them ALREADY had
                                             the guard, and its own comment warned that
                                             FloatToExpStr's loop would not terminate

  Spelling follows sysutils' FloatToStr: `Inf` / `-Inf`, plus `Nan`, with the leading
  space that the positive sign position occupies. NaN prints UNSIGNED even though
  0.0/0.0 carries a set sign bit, which is what FPC does — hence the check sits before
  the sign is emitted.

  The `:w:d` forms print the spelling rather than a padded one: a fixed-decimals request
  cannot be honoured for a value with no digits.

  Run this under a TIMEOUT. A regression here is a hang, not a wrong line. }
program t;
var a, b, z: Double; s: string;
begin
  a := 1.0; b := 0.0;

  z := a / b;                      { +Inf }
  writeln(z);
  write(z); writeln;
  Str(z, s); writeln('[', s, ']');
  writeln(z:0:6);
  writeln(z:12:3);

  a := -1.0; z := a / b;           { -Inf }
  writeln(z);
  Str(z, s); writeln('[', s, ']');
  writeln(z:0:2);

  a := 0.0; z := a / b;            { NaN — unsigned, despite the sign bit }
  writeln(z);
  Str(z, s); writeln('[', s, ']');
  writeln(z:0:2);

  { finite controls: the ordinary path must be untouched }
  z := 1.0;      writeln(z);
  z := -2.5;     writeln(z);
  z := 0.0;      writeln(z);
  z := 1.0e300;  writeln(z);
  z := 3.5;      writeln(z:0:2);
  z := -0.125;   writeln(z:8:3);
end.

program test_puint8_no_compiler_spew;
{ A program naming `puint8` must compile QUIETLY.

  FindTypeAlias carried a leftover debug dump keyed on that exact name: a miss
  there is normal (puint8 resolves through the pointer-alias path afterwards),
  but the miss printed the entire alias table to STDOUT before the fallback
  succeeded. So any C-interop Pascal source using an ordinary uint8-pointer
  name got a dozen lines of compiler internals mixed into its build output —
  and then compiled fine, which is why nothing caught it.

  The assertion is on the COMPILER's output, not this program's; see the
  Makefile rule. }
var
  x: puint8;
  b: Byte;
begin
  b := 7;
  x := @b;
  WriteLn('puint8 ok=', x^);
end.

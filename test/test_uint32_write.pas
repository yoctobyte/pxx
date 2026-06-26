program test_uint32_write;

{ writeln of a 32-bit unsigned (LongWord/Cardinal) with bit 31 set, and of
  INT_MIN, must print the correct decimal on every target. arm32's integer
  formatter used a SIGNED divide (sdiv) for both the unsigned path (garbage for
  values >= 2^31) and the signed magnitude (garbage for INT_MIN, whose negation
  overflows back to 0x80000000). Both now use udiv over the non-negative
  magnitude. See bug-arm32-writeln-longword-high-bit. Cross-compared arm32 vs
  x86-64 oracle in `make test`. }

var c: LongWord; i: Integer;
begin
  c := 100;          writeln(c);
  c := 4294967295;   writeln(c);
  c := 2147483648;   writeln(c);
  c := 3000000000;   writeln(c);
  c := 4294967295;   writeln(c:12);
  i := -1;           writeln(i);
  i := -2147483648;  writeln(i);
  writeln(i:14);
  i := 2147483647;   writeln(i);
end.

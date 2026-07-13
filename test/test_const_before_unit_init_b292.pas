{ CONSTANT initializers must be in place BEFORE any unit's initialization section runs.

  They ARE constants: a `const` array's contents cannot depend on what an initialization
  section does, but the reverse is emphatically true -- fpjson's initialization reads a class
  const (`FElementSep := ElementSeps[FCompressedJSON]`) to set up its separators.

  With the old order (unit init first, const initializers second) that read all zeros, and
  every JSON document fpjson formatted came out with no braces, no colons and no commas. The
  structure was right; the punctuation was simply absent. Silently.

  A constant that does not hold its value until after the program has started running is not
  a constant. }
program test_const_before_unit_init_b292;
uses constinit;
begin
  { what the unit's initialization section captured -- it read a class const }
  writeln('captured by init: [', TD.Captured, ']');
  writeln('unit const      : [', Seps[False], ']');
end.

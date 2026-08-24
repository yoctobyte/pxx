{ An INFERRED variable keeps the whole pointer identity of what it was inferred
  from, not two fifths of it.

  A typed pointer is five fields: the immediate pointee, the number of levels,
  and the ultimate base. InferSymTypeFromNode copied the pointee and left depth
  at 0 and base at tyUnknown, which reads as "not a typed pointer" to every
  predicate that consults the triple. So `var q := pp` over a `pp: ^PChar` lost
  the char-ness one level in, and `q^` printed the ADDRESS while `pp^` on the
  line above printed the string.

  The oracle is the EXPLICITLY TYPED twin, printed beside each inferred row:
  every pair must match, and the explicit half is separately known to match fpc
  3.2.2 (test_pchar_pointer_to_pchar.pas). FPC cannot compile this file itself —
  inline `var` in a statement block is a pxx/Delphi dialect form, not objfpc —
  so a same-program twin is the honest oracle rather than an .expected copied
  from somewhere it was never produced.

  Both sources that record depth are exercised: a SYMBOL (exact) and a PChar
  cast (exact by definition). The shapes whose source records no depth — a
  record field and a function result — are deliberately absent; they cannot be
  right yet, and
  bug-p-dereferencing-a-function-result-of-pointer-to-pchar-loses-the-shape is
  where that is tracked.
  feature-a-typeref-migrate-consumers }
program test_inferred_pointer_keeps_its_depth;
{$mode objfpc}{$H+}
type PPC = ^PChar;
var base: AnsiString; p0: PChar; pp: PPC;
    xq: PPC; xr: PChar;
begin
  base := 'alpha';
  p0 := PChar(base);
  pp := @p0;
  xq := pp;
  xr := p0;

  { two levels, from a symbol that records depth 2 over a char base }
  var q := pp;
  WriteLn(q^,        ' | ', xq^);
  WriteLn('x' + q^,  ' | ', 'x' + xq^);
  WriteLn(q^ = 'alpha', ' | ', xq^ = 'alpha');

  { one level, same source shape }
  var r := p0;
  WriteLn(r,         ' | ', xr);
  WriteLn('y' + r,   ' | ', 'y' + xr);
  WriteLn(Length(AnsiString(r)), ' | ', Length(AnsiString(xr)));

  { one level, from a PChar CAST rather than a symbol }
  var c := PChar(base);
  WriteLn(c,         ' | ', xr);
  WriteLn('z' + c,   ' | ', 'z' + xr);
end.

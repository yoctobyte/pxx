program test_set_low_high_element_bounds;
{ `Low(s)` / `High(s)` on a SET variable answer the ELEMENT type's bounds. They
  used to answer 0 and -1 — `Length(x) - 1` reached through the fallback at the
  bottom of both intrinsics — so `for i := Low(s) to High(s)` ran ZERO times,
  silently, since 0..-1 is a legal empty range.

  The `set of 1..10` row is the one that needed new storage: an anonymous
  subrange element collapses to tyInteger and its bounds were evaluated by
  ParseSetElemSpec and then discarded, so there was nothing to answer with.
  bug-p-low-and-high-of-a-set-do-not-answer-the-element-bounds }
{$mode objfpc}

type
  TE = (eA, eB, eC);
  TSA = set of 1..10;
  TSE = set of TE;

var
  sb: set of Byte;
  ss: set of 1..10;
  se: set of TE;
  sc: set of Char;
  sa: TSA;
  sae: TSE;
  i, n: Integer;
  e: TE;
begin
  writeln('a ', Low(sb), '|', High(sb));
  writeln('b ', Low(ss), '|', High(ss));
  writeln('c ', Ord(Low(se)), '|', Ord(High(se)));
  writeln('d ', Ord(Low(sc)), '|', Ord(High(sc)));
  { the same two shapes through a NAMED set type, which carries the element
    identity in the alias table rather than on the symbol }
  writeln('e ', Low(sa), '|', High(sa));
  writeln('f ', Ord(Low(sae)), '|', Ord(High(sae)));
  { the loop this was really about }
  n := 0;
  for i := Low(ss) to High(ss) do Inc(n);
  writeln('g ', n);
  n := 0;
  for e := Low(se) to High(se) do Inc(n);
  writeln('h ', n);
  { …and that membership still works over the same variables, so the bounds
    change did not disturb the set representation }
  ss := [2, 4];
  writeln('i ', 2 in ss, '|', 3 in ss);
  se := [eB];
  writeln('j ', eB in se, '|', eC in se);
  writeln('OK');
end.

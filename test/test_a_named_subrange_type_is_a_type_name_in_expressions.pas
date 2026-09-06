{ A named SUBRANGE type is a type NAME, and the places that take a type name
  must all take it. Three doors asked the same question and two of them had
  never been told subranges exist:

    for x in T            iterate T's whole range        (tforin1)
    T.member              scoped member access           (tenum3)
    GetEnumName(TypeInfo(T), ..)   the members' names    (tenum3)

  Low(T)/High(T) was the FOURTH door and was fixed first
  (bug-a-low-high-of-a-named-subrange-answer-the-base-type); `for x in T` is the
  identical question through a different door, so it reads the same
  AliasIsSub/AliasSubLo/AliasSubHi columns rather than growing a second source
  of a subrange's bounds.

  THE BOUNDS ARE DELIBERATELY NOT 0..N-1 anywhere in this file. An enum's range
  IS 0..Count-1, and the for-in builder is shared with the enum spelling, so a
  bug that ignored the subrange bounds and iterated the base type from zero
  would print a plausible ascending run. `IntRange = 3..7` sums to 25; iterating
  0..7 gives 28 and 0..4 gives 10, so the total alone separates all three.

  The inline-loop-variable spelling (`for var x in T`) is NOT asserted here:
  fpc 3.2.2 has no inline loop variables, so there is no oracle value for it and
  a row would be asserting our own output back at us. }
program test_a_named_subrange_type_is_a_type_name_in_expressions;
uses typinfo;
type
  TEnum2 = (zero, first, second, third);
  IntRange = 3..7;
  TLetter  = 'c'..'f';
  TRange1  = first..second;
var
  i, sum: LongInt;
  c: Char;
  e: TEnum2;
  R1: TRange1;
  n: LongInt;
begin
  { for-in over an INTEGER subrange: the values, then the total. }
  Write('intrange:');
  sum := 0;
  for i in IntRange do
  begin
    Write(' ', i);
    sum := sum + i;
  end;
  Writeln('  sum=', sum);

  { …over a CHAR subrange. A subrange carries its BASE kind, so the loop
    variable is a Char and prints letters -- an integer-only path prints 99..102
    and is visibly a different answer, not a subtly wrong one. }
  Write('letters:');
  for c in TLetter do
    Write(' ', c);
  Writeln;

  { …and over a subrange OF AN ENUM: ordinals 1..2 of TEnum2, not 0..1. The
    loop variable is the BASE ENUM and not an integer -- fpc refuses a LongInt
    here ("got TEnum2 expected LongInt"), which is the oracle telling us the
    element type of this loop, so Ord() is what makes the ordinal printable. }
  Write('enumsub:');
  n := 0;
  for e in TRange1 do
  begin
    Write(' ', Ord(e));
    n := n + 1;
  end;
  Writeln('  count=', n);

  { Scoped member access through the SUBRANGE's name. The members belong to the
    BASE enum; `second` is ordinal 2 of TEnum2 and 2 is outside 0..1, so a
    resolution that renumbered members relative to the subrange would print 1. }
  R1 := TRange1.second;
  Writeln('scoped=', Ord(R1));
  R1 := TRange1.first;
  Writeln('scoped=', Ord(R1));

  { GetEnumName over TypeInfo of the SUBRANGE. This row SEGFAULTED before the
    fix rather than printing anything: TypeInfo returned the alias's typedata
    and GetEnumName walked it as an enum's member table. A subrange of an enum
    answers its BASE enum's RTTI, so the names resolve. }
  Writeln('name2=', GetEnumName(TypeInfo(TRange1), 2));
  Writeln('name1=', GetEnumName(TypeInfo(TRange1), 1));
end.

{ `Insert([1, 3, 5], t, i)` -- an ELEMENT LIST as the inserted value. The splice
  form already worked for a NAMED source array and the one-element form for a
  SCALAR; only the list spelling was wrong, and it was wrong in the exact way
  this intrinsic's own comment records fixing for the named-array form: it stored
  the source's HANDLE as if it were one element. `Insert([1,3,5], t, 0)` into a
  nil array gave `Length: 1` holding an ADDRESS where fpc gives `1 3 5`. The
  sibling of a fixed double case (tarray12).

  `[...]` is a set until something names its element type. Here the DESTINATION
  names it and is argument two of the same call, already parsed -- which is why
  this is a fix and not a refusal. Its cousin `Concat([1,2,3],[6,8,10])` has no
  destination to ask and is deliberately refused by name; nothing here should be
  read as licence to guess an element type where nothing names one.

  ALL THREE SOURCE SPELLINGS ARE IN THIS FILE and the first two are the ones that
  already worked. The claim is not "a list can be inserted" -- it is "a list is
  inserted the SAME WAY a named array is", so the comparison has to be visible
  rather than remembered. Every row prints CONTENTS, never just Length: the
  defect produced a plausible LENGTH (1) and only the value gave it away, and an
  insert that dropped or misplaced elements would keep a correct length too.

  The index rows cover the clamps in both directions, because a list source and a
  scalar source take different arms to the same clamp. }
program test_insert_takes_an_element_list_like_a_named_array;
{$mode objfpc}
type
  TA = array of LongInt;
  TC = array of Char;
var
  t, u: TA;
  c: TC;

procedure Show(const nm: string; const a: TA);
var k: LongInt;
begin
  Write(nm, ' len=', Length(a), ':');
  for k := 0 to High(a) do Write(' ', a[k]);
  Writeln;
end;

function Init5: TA;
var k: LongInt;
begin
  SetLength(Result, 5);
  for k := 0 to 4 do Result[k] := k;
end;

var k: LongInt;
begin
  { the two spellings that already worked, as the comparison }
  t := Nil; u := TA.Create(7, 8);
  Insert(u, t, 0);          Show('named ', t);
  t := Nil;
  Insert(9, t, 0);          Show('scalar', t);

  { …and the one this change adds }
  t := Nil;
  Insert([7, 8], t, 0);     Show('list  ', t);

  { into a populated array, in the middle }
  t := Init5;
  Insert([1, 3, 5], t, 2);  Show('mid   ', t);

  { an EMPTY list must leave the destination alone -- it is also the one row
    whose right answer equals the do-nothing answer, so it is labelled and the
    rows above are what make it readable. }
  t := Init5;
  Insert([], t, 0);         Show('empty ', t);

  { both index clamps }
  t := Init5;
  Insert([1, 3, 5], t, -1); Show('below ', t);
  t := Init5;
  Insert([1, 3, 5], t, 6);  Show('above ', t);

  { a Char element list, so the element type is carried from the destination and
    not guessed from the literal }
  c := Nil;
  Insert(['b', 'd'], c, 0);
  Write('chars  len=', Length(c), ':');
  for k := 0 to High(c) do Write(' ', c[k]);
  Writeln;
end.

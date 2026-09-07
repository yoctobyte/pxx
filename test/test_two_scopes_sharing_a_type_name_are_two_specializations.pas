program test_two_scopes_sharing_a_type_name_are_two_specializations;
{ A SPECIALIZATION IS KEYED ON THE CONCRETE ARGUMENT'S NAME, so two different
  types that happen to share one spelling are the question that key cannot
  answer by itself. Here a routine-local `TRec` of 4 bytes and a unit-level
  `TRec` of 16 both specialize one template, and they must mint TWO classes.

  THE SIZES ARE THE READOUT AND THEY ARE DELIBERATELY UNEQUAL. Give the two
  records the same layout and a single shared specialization prints the right
  answer twice -- the wrong mint and the right one become indistinguishable,
  which is the whole trap this file exists to avoid. 4 against 16 cannot be
  produced by one class.

  FIELDS ONLY, AND THAT IS THE FIXTURE'S REACH RATHER THAN AN OMISSION. Put a
  METHOD on the template and the same program stops before any of this is
  reached: a routine-local specialization's method body is spliced where the
  parser will not take a method implementation --
  `expected ':' before '.'`, near `; end ; function TB$87 >>> . Size :` --
  which is an anchor defect and nothing to do with naming. Widen this fixture
  the day that wall is gone, and not before: an assertion that cannot compile
  is not a stricter assertion.
  IT LOCKS IN A CORRECT ANSWER RATHER THAN GUARDING A FIX, and has no positive
  control worth the name: pin v407 refuses this file for an unrelated reason (it
  cannot parse the generic class body at all), so "the pin differs" says nothing
  about the key. What makes the fixture worth its line is the OPPOSITE property
  -- the hypothesis it retires was asked twice and answered by reading both
  times, and a row that prints 4 and 16 answers it in a second.

  Oracle: fpc 3.2.2 prints both rows exactly as below.
  bug-p-a-nested-specialization-is-named-by-its-alias-so-one-name-serves-every-outer-specialization }
{$mode objfpc}{$H+}
type
  generic TBox<T> = class
    v: T;
  end;
  TRec = record a, b, c, d: LongInt; end;    { unit-level: 16 bytes }

procedure Outer;
type
  TRec = record a: LongInt; end;             { routine-local: 4 bytes }
  TB   = specialize TBox<TRec>;
var b: TB;
begin
  b := TB.Create;
  WriteLn('inner  ', SizeOf(b.v));
end;

type TBU = specialize TBox<TRec>;            { the UNIT-level TRec }
var u: TBU;
begin
  Outer;
  u := TBU.Create;
  WriteLn('outer  ', SizeOf(u.v));
end.

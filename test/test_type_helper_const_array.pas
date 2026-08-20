program test_type_helper_const_array;
{ feature-pascal-type-helpers v3: a helper's typed const ARRAY, reached through
  the helper's name, through the TARGET TYPE's name, and from a helper body.
  `UInt32.SIZED_SIGN_MASK[i]` is how generics.helpers spells it.

  This was the last open v3 item and it turned out NOT to be a helper gap at
  all: it failed identically through the helper's own name, because a helper is
  a record and a record's const section was parsed with no owner, so a typed
  const never entered the ClassConst registry. Fixing
  bug-p-two-classes-typed-consts-of-the-same-name-collide made all three
  spellings work at once, through the registry the type-name receiver already
  used — which is why no typed-const path was added to the helper code.

  Values are the array's own, so a wrong element or a wrong owner shows up as a
  different power of two rather than a crash. }
type
  TU32Helper = record helper for UInt32
    const SIZED: array[1..4] of UInt32 = ($80, $8000, $800000, $80000000);
    class function Pick(i: Integer): UInt32; static;
  end;
class function TU32Helper.Pick(i: Integer): UInt32; begin Pick := SIZED[i]; end;
var i: Integer;
begin
  Writeln('helper-name : ', TU32Helper.SIZED[2]);
  Writeln('TYPE-name   : ', UInt32.SIZED[4]);
  Writeln('from body   : ', UInt32.Pick(3));
  for i := 1 to 4 do Write(UInt32.SIZED[i], ' ');
  Writeln;
end.

{ `PArr = ^TArr` written ABOVE `TArr = array[..] of T`.

  Ordinary Pascal, and the shape FPC's own compiler sources use --
  `PHashItemList = ^THashItemList;` sits above
  `THashItemList = array[0..N] of THashItem` in cclasses.pas. It was the last
  PARSER wall on the FPC compiler-source march; before this, `cclasses` and the
  three units behind it stopped at `undefined variable (StrIndex)`.

  ParseTypeKind's `^T` arm takes the pointee's element shape from the ArrType
  entry, and its own comment already recorded the gap: *"A FORWARD `PA = ^TA`
  ahead of TA's own declaration is not covered -- the entry does not exist yet
  -- and falls back to the old default."* The fix is in
  ResolvePendingPointerAliases, which exists to run after the type section,
  where the entry does exist.

  IT WAS NOT MERELY A STRIDE FALLBACK, which is what the comment suggests. With
  the element record lost the construct is REFUSED, and it is refused in two
  different voices depending on the spelling -- `a value of this type has no
  members` for `p^[i].f`, `Integer has no members` for `with p^[i] do f`. Row
  `class field` is the third voice and the reason this is a bug and not a
  diagnostic complaint: through a CLASS FIELD the same shape does not refuse at
  all. It compiled, exited 0, and read 0 where fpc reads 42.

  The DECLARATION ORDER rows are the controls, and they are the whole argument:
  every forward row has an in-order twin that worked before the fix and must
  keep working. A declaration order changing whether a program parses is the
  tell the pointer-to-pointer arm of the same routine already names.

  Every row is fpc 3.2.2's own output, byte for byte. }
program test_forward_pointer_to_array_type;

type
  TItem = record
    hv       : LongWord;
    StrIndex : Integer;
  end;

  { FORWARD: the pointer names an array type declared below it }
  PFwd = ^TFwd;
  TFwd = array[0..3] of TItem;

  { IN-ORDER: the control, which has always worked }
  TOrd = array[0..3] of TItem;
  POrd = ^TOrd;

  { forward to an array of a SCALAR — the stride half, with no record involved }
  PNum = ^TNum;
  TNum = array[0..3] of Int64;

  TBox = class
    fwd : PFwd;
    function Read1: Integer;
  end;

var
  gf : TFwd;
  go : TOrd;
  gn : TNum;
  pf : PFwd;
  po : POrd;
  pn : PNum;
  b  : TBox;

function TBox.Read1: Integer;
begin
  Read1 := fwd^[1].StrIndex;
end;

begin
  gf[1].StrIndex := 42;
  go[1].StrIndex := 42;
  gn[2] := 1234567890123;
  pf := @gf;
  po := @go;
  pn := @gn;

  writeln('forward  read field  : ', pf^[1].StrIndex);
  writeln('in-order read field  : ', po^[1].StrIndex);

  with pf^[1] do
    writeln('forward  with-scope  : ', StrIndex);
  with po^[1] do
    writeln('in-order with-scope  : ', StrIndex);

  pf^[2].StrIndex := 7;
  po^[2].StrIndex := 7;
  writeln('forward  write field : ', gf[2].StrIndex);
  writeln('in-order write field : ', go[2].StrIndex);

  writeln('forward  scalar elem : ', pn^[2]);

  b := TBox.Create;
  b.fwd := @gf;
  writeln('forward  class field : ', b.Read1);
end.

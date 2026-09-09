{ `@X` as an ELEMENT of a typed const array.

  ConstEval cannot evaluate `@` and does not CONSUME it either, so the
  array-constant loop's fallback left TokPos on the `@`, spun, and counted the
  same token once per declared slot until the length check tripped:
  `too many array constant elements`, with TokPos still on the FIRST element --
  a size complaint about a correct size. The scalar spelling
  (`const P: Pointer = @G`) has always worked; only the element position was
  missing, and it is the FOURTH instance of this exact desync in one loop
  (string literal, PChar, set, now `@`), which is why the fix is the shared
  TryParseInitValForm rather than a fourth hand-written arm.

  rtl-generics' generics.defaults.pas is the real consumer: its
  `ComparerInstances` table is twenty rows of `@TComparerService.SelectXComparer`.

  Both value forms are asserted, because they are different emitter kinds --
  2 = AN_PROCADDR for a routine, 4 = AN_ADDR for a variable -- and a fix that
  wired only one would pass a test that asserted only one.
  bug-p-an-address-of-element-in-a-const-array-is-counted-as-many }
program test_an_address_of_element_in_a_const_array;
{$mode delphi}
type
  TSelectFunc = function (A: Pointer; ASize: SizeInt): Pointer;

function Plain(A: Pointer; ASize: SizeInt): Pointer;
begin
  Result := Pointer(PtrUInt(ASize) + 200);
end;

var
  G: Integer = 3;

const
  Table: array[0..2] of Pointer = (@Plain, @G, nil);

procedure Local;
const
  LTable: array[0..1] of Pointer = (@Plain, @G);
begin
  WriteLn('local call  ', PtrUInt(TSelectFunc(LTable[0])(nil, 5)));
  WriteLn('local deref ', PInteger(LTable[1])^);
end;

begin
  WriteLn('call  ', PtrUInt(TSelectFunc(Table[0])(nil, 7)));
  WriteLn('deref ', PInteger(Table[1])^);
  WriteLn('nil   ', Table[2] = nil);
  Local;
end.

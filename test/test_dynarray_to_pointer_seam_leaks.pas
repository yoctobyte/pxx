program test_dynarray_to_pointer_seam_leaks;
{ A DYNAMIC ARRAY reaching a pointer destination gets an owner.

  The same shape as the eight string seams
  (bug-a-a-managed-string-reaching-a-pointer-destination-has-no-owner), one
  managed kind over: a Pointer/PChar destination keeps an address and retains
  nothing, so a handle that arrives carrying a +1 nobody holds can never be
  released -- it was never a symbol. All three spellings read frees=0, every
  array leaked:

    Pointer(MkArr(i))                the pointer cast          921 -> 2
    TakeQ(MkArr(i))  TakeQ(p: Pointer)  the pointer parameter  921 -> 2
    q := Pointer(MkArr(i))           the assignment            921 -> 2
    TakeQ(Pointer(a))  a a named local  CONTROL, unmoved       921/919 both

  The control is the row that says this is ownership: the same call through a
  named local was always clean, because the local owned the array. After the fix
  all four read 921/919 live=2 -- the three leaking spellings land exactly on the
  control rather than somewhere near it.

  This whole program, against 39e033c85335 (the binary immediately before the
  fix): live 9976 -> 14 against a bound of 50, allocs 10975 either way -- same
  traffic, so the delta is ownership. REJECTED by the pre-fix binary (rc=1),
  which is the check that says it can fail at all. Identical on x86-64, aarch64,
  arm32 and riscv32.

  NO i386 ROW, and that is a limit of the target rather than an omission: i386
  refuses this program outright with "target i386: arrays not yet supported" --
  `Length(a)` alone is enough. A cross row here would compare against a file
  that was never built, which is a comparison that cannot fail.

  WHY IT NEEDED ITS OWN PARK. A dyn-array-typed node already reads tyPointer, so
  the string park could not see these however it was spelled: the test has to be
  the node's dyn DEPTH, not its type tag. And the temp is a different object --
  a dyn-array local carries an element type and a nesting depth, and its
  scope-exit release is PXXDynArrayRelease reading that SYMBOL's layout
  descriptor, which a string temp does not have.

  Which is why the element shapes below are not decoration. A plain
  `array of Integer` needs no element walk at all; `array of AnsiString`,
  `array of array of Integer` and `array of TRec` each make the descriptor do
  real work, and a wrong element type would show up as a double free rather than
  as a leak. They are run under -dPXX_HEAP_DEBUG for exactly that reason.

  FPC ORACLE, and the one line it will not take. `TakeQ(MkArr(i))` -- the
  IMPLICIT conversion to a Pointer parameter -- is "Incompatible type for arg
  no. 1: Got TIntArr, expected Pointer" there, exactly as the string family's
  implicit arm is; pxx accepts it deliberately and accepting what FPC rejects is
  not a defect. With that one call spelled `TakeQ(Pointer(MkArr(i)))` the whole
  program compiles under FPC and prints `sink=7000 / last=3 head=1000`, which is
  byte for byte what pxx prints for both spellings. So the OUTPUT has an oracle
  and the leak COUNT does not -- FPC has its own lifetime for a function result
  -- which is why the bound below is absolute rather than differential.
  bug-a-a-dynamic-array-reaching-a-pointer-destination-has-no-owner }
{$mode objfpc}{$H+}
uses sysutils;

const N = 1000;

type
  TIntArr = array of Integer;
  TStrArr = array of AnsiString;
  TNest   = array of array of Integer;
  TRec    = record S: AnsiString; K: Integer; end;
  TRecArr = array of TRec;

var i, sink: Integer;
    q: Pointer;
    a: TIntArr;

function MkArr(n: Integer): TIntArr;
begin SetLength(MkArr, 3); MkArr[0] := n; end;

function MkStr(n: Integer): TStrArr;
begin SetLength(MkStr, 2); MkStr[0] := 's' + Chr(48 + n mod 10); MkStr[1] := 't'; end;

function MkNest(n: Integer): TNest;
begin SetLength(MkNest, 2); SetLength(MkNest[0], 2); MkNest[0][0] := n; end;

function MkRecA(n: Integer): TRecArr;
begin SetLength(MkRecA, 2); MkRecA[0].S := 'r' + Chr(48 + n mod 10); MkRecA[0].K := n; end;

procedure TakeQ(p: Pointer);
begin
  if p <> nil then Inc(sink);
end;

begin
  sink := 0;

  { the pointer CAST }
  for i := 1 to N do TakeQ(Pointer(MkArr(i)));

  { the pointer PARAMETER, no cast in the source }
  for i := 1 to N do TakeQ(MkArr(i));

  { the ASSIGNMENT }
  for i := 1 to N do
  begin
    q := Pointer(MkArr(i));
    if q <> nil then Inc(sink);
  end;

  { CONTROL: a named local already owned it }
  for i := 1 to N do
  begin
    a := MkArr(i);
    TakeQ(Pointer(a));
  end;

  { element shapes that make the layout descriptor do real work — a wrong
    element type here is a double free, not a leak }
  for i := 1 to N do TakeQ(Pointer(MkStr(i)));
  for i := 1 to N do TakeQ(Pointer(MkNest(i)));
  for i := 1 to N do TakeQ(Pointer(MkRecA(i)));

  WriteLn('sink=', sink);
  WriteLn('last=', Length(a), ' head=', a[0]);
end.

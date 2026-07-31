{ bug-pascal-array-of-pointer-deref-loses-the-record-type: a VAR of a named
  array-type ALIAS whose element is a pointer-to-record (like typinfo's
  `TPropList = array[0..511] of PPropInfo`) lost the pointee record id: only
  the array element's FIRST field resolved via `arr[i]^.Field` (a name that
  happened to also be the first field of whatever OTHER pointer type was last
  parsed in the compilation unit); every later field errored "no such member".
  Root cause: the array-type-alias table (ArrType*) had no slot for a pointer
  element's pointee record id, so consumers of the alias (a var/field/param
  declaration) fell back to reading the single global LastTypePointerElemRec,
  whatever unrelated pointer-typed declaration had left it holding. }
program test_arr_of_ptr_elemrec_b354;

type
  TInner = record
    A: Integer;
    B: Integer;
    C: Integer;
  end;
  PInner = ^TInner;
  TInnerList = array[0..3] of PInner;

  { A record whose first field is also named 'A' -- if the array's element
    pointee record id were lost and something else's pointer type leaked in
    instead, `lst[i]^.A` could silently "succeed" against the WRONG record
    while `.B`/`.C` failed loudly. Declaring it, and a stray pointer LOCAL
    var below, reproduces the leaking-global shape that broke typinfo's
    TPropList (many pointer-typed locals parsed between the array alias's
    definition and its use). }
  TDecoy = record
    A: Integer;
  end;
  PDecoy = ^TDecoy;

var
  lst: TInnerList;
  rec: TInner;
  i: Integer;

procedure Touch;
var d: PDecoy;   { the LAST pointer-typed declaration before `lst` is used }
begin
  d := nil;
  if d <> nil then Halt(1);
end;

begin
  Touch;
  rec.A := 10; rec.B := 20; rec.C := 30;
  i := 0;
  lst[i] := @rec;
  WriteLn(lst[i]^.A, ' ', lst[i]^.B, ' ', lst[i]^.C);
end.

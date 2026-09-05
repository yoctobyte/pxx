program test_record_name_cast_strides_by_its_record;
{ `TRec(ptr)` is a pxx extension meaning `PRec(ptr)` without a declared PRec,
  and the arm that builds it says it "mirrors the pointer-alias path". For `[i]`
  it did not.

  NO FPC ORACLE BY CONSTRUCTION, and that is not the same as no verdict. fpc
  3.2.2 refuses both spellings here -- `Illegal type conversion: "Pointer" to
  "TRec"` for the record name, `Array type required` for indexing the pointer --
  so accepting them is a pxx extension and not a defect. Answering DIFFERENTLY
  in two spellings of one concept is, which is what this file asserts: every row
  is the alias spelling and the record-name spelling of the same access.

  Before the fix, with a[0..2].a = 10 11 12:

      PRec(raw)[0..2].a   10 11 12
      TRec(raw)[0..2].a   10  0  0     element 0 right BY COINCIDENCE

  because the cast node's ASTIVal was stamped 0 to mean "plain reinterpret, no
  adapter" and ir.inc reads that field as an ALIAS INDEX -- so 0 was alias row
  ZERO, whatever the program declared first, and the stride came from an
  unrelated type.

  THE WRITE ROWS ARE THE POINT, AND THEY MUST READ BACK THROUGH `t`, NOT
  THROUGH THE CAST. `TRec(raw)[1].a := 71` left t[1].a at 11 and then read 71
  back through the same cast, because the read went to the same wrong address.
  A row comparing a store to its own read-back cannot fail on this.
  refactor-p-one-lvalue-path-for-statements-and-expressions }
type
  PRec = ^TRec;
  TRec = record
    a: LongInt;
    arr: array[0..3] of LongInt;
  end;
var
  raw: Pointer;
  t: array[0..2] of TRec;
  i: LongInt;
begin
  t[0].a := 10; t[1].a := 11; t[2].a := 12;
  t[0].arr[2] := 80; t[1].arr[2] := 81; t[2].arr[2] := 82;
  raw := @t[0];

  for i := 0 to 2 do WriteLn('read  alias ', i, ' ', PRec(raw)[i].a);
  for i := 0 to 2 do WriteLn('read  recnm ', i, ' ', TRec(raw)[i].a);
  for i := 0 to 2 do WriteLn('nest  alias ', i, ' ', PRec(raw)[i].arr[2]);
  for i := 0 to 2 do WriteLn('nest  recnm ', i, ' ', TRec(raw)[i].arr[2]);

  { stores, read back through t -- never through the cast that wrote them }
  PRec(raw)[1].a := 71;
  WriteLn('store alias 1 ', t[1].a);
  TRec(raw)[2].a := 72;
  WriteLn('store recnm 2 ', t[2].a);
  PRec(raw)[0].arr[2] := 90;
  WriteLn('nstor alias 0 ', t[0].arr[2]);
  TRec(raw)[1].arr[2] := 91;
  WriteLn('nstor recnm 1 ', t[1].arr[2]);
end.

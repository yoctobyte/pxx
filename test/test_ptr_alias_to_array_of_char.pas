program test_ptr_alias_to_array_of_char;
{$mode objfpc}{$H+}
{ `PCharA(@ca)^[i]` where `PCharA = ^array[..] of Char`.

  The cast arm stamped the -2 PChar ADAPTER whenever `AliasElemTk = tyChar`.
  That is a PROXY for "this points at a character" and it is equally true of a
  pointer to an ARRAY that happens to hold chars. Worse than the wrong adapter:
  -2 goes in the SAME SLOT as aliasIdx, and aliasIdx is the only thing carrying
  AliasPtrElemArrAi -- the pointee's array row -- so the subscript lost its
  element type and the AN_INDEX came out tk=0 (tyUnknown, measured with
  PXXDBG=a.ast). TypeSlotSize(tyUnknown) is a 4-byte read.

  The rows that matter and why each can FAIL:

  * `assigned=` was ALWAYS correct and is here as the contrast, not as cover:
    a declared Char target forces the right width, so an assignment-only test
    would have passed throughout. The defect lives in RVALUE position.
  * `ord=` is the sharpest row. It printed 1644192610 against 98 -- a number,
    from a truthful-looking operator, with no diagnostic.
  * `inline=`/`idx2=` print the char itself; they read 7061644217361130338 and
    varied run to run, because the read ran past the element.
  * `viaptr=` goes through a pointer VARIABLE, which asks the SYMBOL's
    SymPtrElemArrAi and never passes through the stamp. It was correct before
    the fix and must stay correct: it is the row that proves the two routes now
    agree rather than that either one moved.

  NO NUMERIC ELEMENT KIND COULD EVER FAIL THIS -- byte/word/integer/int64/
  double all matched fpc 3.2.2 before the fix, because none of them reaches a
  branch keyed on tyChar. The one element kind that looks least likely to have
  a width bug was the only one that had one, which is why the numeric rows are
  below as controls rather than as coverage.
  bug-p-a-pointer-alias-to-an-array-of-char-takes-the-pchar-adapter }
type
  TCharA = array[0..3] of Char;
  PCharA = ^TCharA;
  TIntA  = array[0..3] of Integer;
  PIntA  = ^TIntA;
  TDblA  = array[0..3] of Double;
  PDblA  = ^TDblA;
  PCh    = ^Char;
var
  ca: TCharA; ia: TIntA; da: TDblA;
  p: PCharA; c: Char; n: Integer; s: AnsiString;
begin
  ca[0] := 'a'; ca[1] := 'b'; ca[2] := 'c'; ca[3] := 'd';
  ia[1] := 33; da[1] := 5.5;

  c := PCharA(@ca)^[1];
  WriteLn('assigned=', c);
  n := Ord(PCharA(@ca)^[1]);
  WriteLn('ord=', n);
  WriteLn('inline=', PCharA(@ca)^[1]);
  WriteLn('idx2=', PCharA(@ca)^[2]);
  p := @ca;
  WriteLn('viaptr=', p^[1]);

  WriteLn('int=', PIntA(@ia)^[1]);
  WriteLn('dbl=', PDblA(@da)^[1]:0:1);

  { the -2 adapter's OWN case: a bare ^Char alias over a managed string still
    skips the 8-byte length prefix. This is what the guard must not break. }
  s := 'hello';
  WriteLn('bare=', PCh(s)^);
  WriteLn('pchar=', PChar(s)[2]);
end.

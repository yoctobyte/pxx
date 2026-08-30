{ `p^[i]` where p points at an ARRAY whose ELEMENT is a pointer.

  `tk = tyPointer` on a deref node is AMBIGUOUS -- it means "the pointee is a
  pointer" and also "the pointee is an array whose ELEMENT is a pointer" -- and
  three readers took the first meaning for the second shape. The element type is
  the only thing that decides which, which is why an Integer element was always
  fine and a pointer element segfaulted before main got anywhere.

  Rows 1-4 are the defect, on READ and on WRITE, and each is a different reader:
  a pointer element (pointer-arithmetic lowering), a record-pointer element with
  a field behind it, an AnsiString element (the managed-string index path), and
  a PChar element written INLINE (the PChar shape reader, whose failure is
  silent -- it printed a decimal address next to a correct value from the very
  same expression via a variable).

  Rows 8-10 are the controls. An Integer element could never reach any of the
  three arms, a direct index of the same array bypasses the deref entirely, and
  Low/High/SizeOf of `p^` answer about the ARRAY -- if a fix made `p^` stop
  being an array, row 10 is what says so.

  NON-VACUOUS, measured per row on `pinned` and NOT from this file, which stops
  at the first COMPILE error and would have hidden everything after it:

    pointer element      SEGFAULT (139)
    record-ptr element   compile error, "dereferenced value is not a pointer"
    AnsiString element   SEGFAULT (139)
    PChar element        SEGFAULT (139), after printing the row's label

  The PChar row is worth its place even so: with only the two LOWERING readers
  fixed it stopped crashing and printed a decimal ADDRESS instead, next to the
  correct text from the very same expression assigned through a variable. That
  intermediate state is what a crash-only test would have called fixed.

  Oracle: fpc -Mobjfpc, all ten rows.
  bug-a-indexing-through-a-pointer-to-an-array-of-pointers-segfaults }
program test_ptr_to_array_of_pointers_index;

type
  TRec  = record x, y: Integer; end;
  PRec  = ^TRec;
  TAPtr = array[0..3] of Pointer;    PAPtr = ^TAPtr;
  TARec = array[0..3] of PRec;       PARec = ^TARec;
  TAStr = array[0..3] of AnsiString; PAStr = ^TAStr;
  TAChr = array[0..3] of PChar;      PAChr = ^TAChr;
  TAInt = array[0..3] of Integer;    PAInt = ^TAInt;

var
  r0, r1: TRec;
  n0: Integer;
  aptr: TAPtr; qptr: PAPtr;
  arec: TARec; qrec: PARec;
  astr: TAStr; qstr: PAStr;
  achr: TAChr; qchr: PAChr;
  aint: TAInt; qint: PAInt;
  pv: Pointer;
  sv: AnsiString;

begin
  n0 := 4242;
  r0.x := 10; r0.y := 11;
  r1.x := 20; r1.y := 21;

  { 1 — a raw pointer element. The read segfaulted: the deref was lowered as
        pointer arithmetic, so element 0's CONTENTS became the base address. }
  aptr[1] := @n0;
  qptr := @aptr;
  pv := qptr^[1];
  WriteLn('1 ', Integer(pv^));
  qptr^[2] := @r1;
  WriteLn('2 ', Integer(PRec(aptr[2])^.x));

  { 3 — a record-pointer element, with a field behind the second caret. }
  arec[0] := @r0; arec[1] := @r1;
  qrec := @arec;
  WriteLn('3 ', qrec^[1]^.x, ' ', qrec^[1]^.y);
  qrec^[1]^.x := 99;
  WriteLn('4 ', r1.x);

  { 5 — an AnsiString element. This one took the MANAGED-STRING index path:
        `p^` was loaded as a string handle and indexed 1-based at stride 1, so
        the element came back as a CHAR. Read, write and Length. }
  astr[1] := 'hello';
  qstr := @astr;
  sv := qstr^[1];
  WriteLn('5 ', sv, ' ', Length(qstr^[1]));
  qstr^[2] := 'wo';
  WriteLn('6 ', astr[2]);

  { 7 — a PChar element INLINE. Silent, not a crash: the same element printed
        correctly through a variable and as a decimal address written direct. }
  achr[1] := 'zz';
  qchr := @achr;
  WriteLn('7 ', qchr^[1]);

  { 8, 9, 10 — the controls. }
  aint[1] := 77;
  qint := @aint;
  WriteLn('8 ', qint^[1]);
  WriteLn('9 ', aptr[1] = @n0, ' ', arec[0]^.x);
  WriteLn('10 ', Low(qrec^), ' ', High(qrec^), ' ', SizeOf(qrec^));
end.

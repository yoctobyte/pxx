{ A CALL RESULT walked through a field and then INDEXED, as an assignment
  target — the arm of ApplyCallResultPtrSuffix that did not get the fix its
  neighbour did.

  The loop captures the CALL's own pointee once, before it starts, and that is
  the right answer only while the walk is still on the call. The `^` arm learnt
  that when the escape census found `GetP^.pi^ := 9` refused with `cannot
  assign Integer to record` — the store's target stamped with the record the
  call points AT — and took a `movedOffCall` guard. The `[` arm, three screens
  down the same loop, kept re-stamping from the call's constants, so

    GetP(raw)^.arr[1] := 44

  was refused with the identical message while the READ of the identical chain
  was correct, and while the same store through every other opener — a plain
  record, a pointer variable, an alias cast, a record-name cast — was accepted.
  fpc 3.2.2 accepts it too.

  ONE ARM OF A DOUBLE CASE FIXED AND THE SIBLING NOT GREPPED FOR, inside the
  routine whose own ticket is about exactly that habit. It was found by an
  opener-by-chain differential (five openers, five chains, read and write; 45
  rows, one red), not by a report.

  THE CONTROL OPENERS ARE THE POINT. Every row below is run through the call
  result AND through a plain pointer variable, and the two must agree — a chain
  that is simply wrong for everyone would pass a call-only test. Expected output
  is fpc 3.2.2's own.
  refactor-p-three-hand-rolled-postfix-loops }
program test_call_result_suffix_after_a_field;
{$mode delphi}

type
  PLongInt = ^LongInt;
  PRec = ^TRec;
  TRec = record
    a: LongInt;
    pi: PLongInt;
    arr: array[0..3] of LongInt;
    n: PRec;
  end;

function GetP(p: Pointer): PRec;
begin
  Result := PRec(p);
end;

var
  r, r2: TRec;
  raw: Pointer;
  vp: PRec;
  iv: LongInt;
begin
  iv := 77;
  r.a := 11; r.pi := @iv; r.arr[1] := 33; r.n := @r2;
  r2.a := 5; r2.arr[2] := 66;
  raw := @r; vp := @r;

  { reads: the call result and the pointer variable must agree }
  WriteLn(GetP(raw)^.arr[1], ' ', vp^.arr[1]);
  WriteLn(GetP(raw)^.n^.arr[2], ' ', vp^.n^.arr[2]);
  WriteLn(GetP(raw)^.pi^, ' ', vp^.pi^);

  { the store that was refused }
  GetP(raw)^.arr[1] := 44;
  WriteLn(r.arr[1]);

  { ...through a second level of pointer, so the guard is exercised after the
    walk has moved off the call more than once }
  GetP(raw)^.n^.arr[2] := 88;
  WriteLn(r2.arr[2]);

  { the neighbour arm that already had the guard, kept as a live row }
  GetP(raw)^.pi^ := 99;
  WriteLn(iv);

  { and the call-relative shapes the guard must NOT change: the walk has not
    moved off the call at the `[` here }
  WriteLn(GetP(raw)^.a);
  GetP(raw)^.a := 12;
  WriteLn(r.a);
end.

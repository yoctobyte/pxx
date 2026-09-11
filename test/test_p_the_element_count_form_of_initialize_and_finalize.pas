{ `Initialize(x, n)` / `Finalize(x, n)` — x is the FIRST OF n CONSECUTIVE
  ELEMENTS, which is how FPC's own RTL spells both wherever the count is not a
  compile-time constant.

  THE STRIDE IS THE INTERESTING ROW AND IT IS `ints`. The layout descriptor
  these lower onto enumerates a record's MANAGED MEMBERS and says nothing about
  its size, so a step derived from the descriptor walks 16 bytes where TRec is
  24 — and then element 1 is finalized at element 0's tail. `TRec` here is
  deliberately `AnsiString; Integer; AnsiString`: TWO managed members with an
  UNMANAGED one wedged between them, so a short step lands inside the record
  rather than neatly on the next one.

  MEASURED, not reasoned: build the compiler with that IR_ARG carrying the
  descriptor-shaped guess 16 instead of `RecSize`, and this program SIGSEGVs
  (rc=139) having printed `before` and nothing else. The stride is load-bearing
  and every row under `before` is downstream of it. `ints` stays `10 11 12 13`
  because a correct Finalize touches no unmanaged member.

  THE MIDDLE OF THE ARRAY, NEVER THE START. `Finalize(a[1], 2)` leaves a[0] and
  a[3] alone, so the rows assert a BOUNDARY in both directions. Starting at a[0]
  would pass with an off-by-one at the bottom and starting at a[3] with one at
  the top.

  `keep` IS THE REFERENCE-NOT-THE-OBJECT ROW. `keep := a[1].S` before the
  Finalize, printed after it: Finalize drops a REFERENCE, so the copy stays
  valid. A bespoke free prints garbage or faults here.

  `again` IS IDEMPOTENCE, and it is not decoration — Finalize nils what it
  releases, so a second pass over the same range must decrement nothing. That
  property is what makes it safe for a container to finalize on Clear and again
  on Destroy.

  `zero` IS THE ROW A REFUSAL WOULD HAVE COST. FPC's own callers reach this with
  a freshly-emptied container (`Finalize(FItems^, FCount)` right after FCount
  became 0), so a non-positive count must be a no-op and not an error.

  THE Initialize HALF HAS A REAL POSITIVE CONTROL AND IT WAS RUN: delete the
  `Initialize(p^, 3)` line and the identical program is Runtime error 216 under
  fpc 3.2.2 and a SEGFAULT under pxx — assigning to an AnsiString field whose
  bytes are $FF releases a garbage handle. So the rows below cannot pass by
  accident of the intrinsic doing nothing. GetMem plus FillChar($FF) is what
  makes that true; a stack array would already be zero and the control could
  not fire.

  Expected output is fpc 3.2.2's for this exact source.
  feature-p-the-element-count-form-of-initialize-and-finalize }
program test_p_the_element_count_form_of_initialize_and_finalize;
{$mode objfpc}{$H+}

type
  PRec = ^TRec;
  TRec = record
    S: AnsiString;
    N: Integer;
    T: AnsiString;
  end;

var
  a: array[0..3] of TRec;
  i: Integer;
  keep: AnsiString;
  p: PRec;

procedure Lens(const tag: AnsiString);
begin
  WriteLn(tag, ' ', Length(a[0].S), Length(a[1].S), Length(a[2].S), Length(a[3].S),
          '/', Length(a[0].T), Length(a[1].T), Length(a[2].T), Length(a[3].T));
end;

function ElemAt(base: PRec; idx: Integer): PRec;
begin
  ElemAt := PRec(PtrUInt(base) + PtrUInt(idx * SizeOf(TRec)));
end;

begin
  for i := 0 to 3 do
  begin
    a[i].S := 'aaa';
    a[i].T := 'bb';
    a[i].N := 10 + i;
  end;
  Lens('before ');

  keep := a[1].S;
  Finalize(a[1], 2);
  Lens('after  ');
  WriteLn('keep    ', keep);
  WriteLn('ints    ', a[0].N, ' ', a[1].N, ' ', a[2].N, ' ', a[3].N);

  Finalize(a[1], 2);
  Lens('again  ');

  Finalize(a[0], 0);
  Lens('zero   ');

  Finalize(a[3], 1);
  Lens('one    ');

  { Initialize over bytes that are NOT references -- the case the intrinsic
    exists for, and the only one where its absence is observable. }
  p := GetMem(3 * SizeOf(TRec));
  FillChar(p^, 3 * SizeOf(TRec), $FF);
  Initialize(p^, 3);
  for i := 0 to 2 do
  begin
    ElemAt(p, i)^.S := 'zz';
    ElemAt(p, i)^.N := i;
  end;
  WriteLn('heap    ', Length(ElemAt(p, 0)^.S), Length(ElemAt(p, 1)^.S), Length(ElemAt(p, 2)^.S));
  WriteLn('heapint ', ElemAt(p, 0)^.N, ElemAt(p, 1)^.N, ElemAt(p, 2)^.N);
  Finalize(p^, 3);
  WriteLn('heapfin ', Length(ElemAt(p, 0)^.S), Length(ElemAt(p, 1)^.S), Length(ElemAt(p, 2)^.S));
  FreeMem(p);
  WriteLn('done');
end.

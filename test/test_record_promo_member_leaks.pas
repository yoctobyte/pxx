{ A PROMOTABLE INT MEMBER of a record or a class.

  The heap tier of a promo value owns an AnsiString payload, exactly as a
  Variant's does. But where a Variant at least had a member kind (5) that the
  CLASS descriptor emitted, a promo member had NO MEMBER KIND AT ALL: the walk
  knew 1 String, 2 DynArray, 3 Record, 4 interface, 5 Variant, 6 NilPy binding,
  and nothing for a promo slot. FieldIsManaged did not recognise one either, so
  it never became a descriptor member in a record or a class.

  Measured before, live blocks over 2000 trips (1000 x 8 for the array rows):

    local record {promo, string}, promo assigned    1904   ->   6
    class field {promo, string}                     1787   ->   7
    dyn array of record with a promo member         7685   ->  21
    array[0..7] of record with a promo member       7578   ->  18

  A record whose ONLY member is a promo measured CLEAN both before and after
  (live=6): with no other managed member the record was never managed, so
  nothing walked it and nothing needed to. It takes a second, recognised member
  to expose the gap, which is why the obvious one-field probe reports success.

  WHY KIND 7 CARRIES A STRIDE. Every other member kind has a width the runtime
  can name: a handle is a pointer, a Variant is 16 bytes. A promo member does
  not — and not because one type's width floats, but because `PromoInt` is not
  one type. It resolves through PromoIntDefaultKind to tyPromoInt64 (16 bytes,
  two 64-bit words) on a 64-bit target and to tyPromoInt32 (8) on a 32-bit one,
  the slot being two NATIVE words by definition; the numbered spellings are
  refused outright on the target they do not match, so the portable spelling is
  the only one a program carries ACROSS targets. The ACTION is therefore one
  thing and the SIZE is not, and a runtime constant would be right on exactly
  half the fleet. The descriptor carries the compiler's own TypeSlotSize answer
  in the member's typeRef word — the discriminated slot kinds 4/5/6 already use
  it that way in an ARRAY descriptor — so the runtime cannot disagree with the
  compiler about a layout, on any target.

  WHY THE SURVIVOR ARM IS THE ONE THAT MATTERS. Describing the member means
  PXXRecordRelease starts releasing it, and PXXRecordRetain had no arm for it
  either. Release without retain does not leak — it DESTROYS SetLength
  survivors. Verified as a control rather than assumed: with the retain arm
  removed and the compiler rebuilt, the survivor rows below report 3/6000 and
  the -dPXX_HEAP_DEBUG build SIGSEGVs. Both halves land together. }
program test_record_promo_member_leaks;
type
  TR = record p: PromoInt; s: AnsiString; end;
  TC = class public p: PromoInt; s: AnsiString; end;
var ok, total: Integer;

procedure Chk(const w: AnsiString; got: Boolean);
begin
  Inc(total);
  if got then Inc(ok) else WriteLn('FAIL ', w);
end;

function PS(const q: PromoInt): AnsiString;
var t: PromoInt;
begin t := q; PS := PXXPromoToStr(@t); end;

{ Survivors across grow / shrink / regrow: the retain half. }
procedure Survivor;
var a: array of TR; j: Integer;
begin
  SetLength(a, 4);
  for j := 0 to 3 do
  begin
    a[j].p := 1; a[j].p := a[j].p * 100000000000000000000; a[j].p := a[j].p + j;
    a[j].s := 'str-payload-long-enough-to-be-heap-' + Chr(48 + j);
  end;
  SetLength(a, 8);
  Chk('grow survivor',   PS(a[1].p) = '100000000000000000001');
  SetLength(a, 2);
  Chk('shrink survivor', PS(a[1].p) = '100000000000000000001');
  SetLength(a, 5);
  Chk('regrow survivor', PS(a[1].p) = '100000000000000000001');
  Chk('regrow string',   a[1].s = 'str-payload-long-enough-to-be-heap-1');
end;

{ Build and drop, record and class: the release half. The Makefile's
  assert_no_leak row is what reads these -- every Chk above passes on a build
  that leaks. }
procedure Dropped;
var r: TR; o: TC;
begin
  r.p := 1; r.p := r.p * 100000000000000000000;
  r.s := 'dropped-str-payload-long-enough-to-be-heap';
  o := TC.Create;
  o.p := 1; o.p := o.p * 100000000000000000000;
  o.s := 'dropped-cls-payload-long-enough-to-be-heap';
  o.Free;
end;

var i: Integer;
begin
  ok := 0; total := 0;
  for i := 1 to 1000 do
  begin
    Survivor;
    Dropped;
  end;
  WriteLn('record-promo-member ', ok, '/', total);
end.

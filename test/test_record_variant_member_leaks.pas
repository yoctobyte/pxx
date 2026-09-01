{ A VARIANT MEMBER OF A RECORD, walked through the record's RTTI descriptor.

  FieldIsManaged knows AnsiString, dynamic arrays and nested records-with-
  managed-fields. It does not know Variant, so RecordDescMember excluded a
  variant member, it never became a descriptor member, and PXXRecordRelease
  never saw it. The CLASS layout descriptor has carried the arm all along
  (ClassFieldNeedsFinal), so a class with a variant field was always fine and a
  RECORD with one was not -- two writers for one question, disagreeing.

  Measured before the fix, dyn array of `record v: Variant; s: AnsiString`,
  1000 trips of 8 elements: live=7357, and the STRING member was reclaimed
  while the variant member was not, which is what identifies the variant as the
  survivor rather than the record or the array.

  WHY THE SURVIVOR ARM IS THE ONE THAT MATTERS. Adding the member to the
  descriptor means PXXRecordRelease starts CLEARING it -- and PXXRecordRetain
  had no kind-5 arm at all, because a class is finalized and never copied by
  value, so that side had never been reached for a variant. Emitting kind 5
  without the retain arm is therefore a release without its retain: SetLength
  shrink retains the survivors and releases the whole old block, so a survivor
  whose variant was cleared but never retained is DESTROYED. Both halves landed
  together for that reason.

  Verified as a real control, not assumed: with the retain arm removed and the
  compiler rebuilt, this file reports bad=9000 under -dPXX_HEAP_DEBUG and
  live=5947 instead of live=7. Note it reports bad=0 WITHOUT poisoning even
  while broken -- the freed block is usually still intact -- so the heap-debug
  run is the one that makes the double free loud, and a plain `r2 := r1` copy
  never reaches PXXRecordRetain at all and cannot see any of this. }
program test_record_variant_member_leaks;
type TR = record v: Variant; s: AnsiString; end;
var ok, total: Integer;

{ Compared INLINE, and passing the variant to a helper would be the obvious
  spelling: `Chk('grow', a[1].v, '...')` with a `const got: AnsiString`
  parameter. Do not -- that shape carries a SEPARATE, pre-existing leak of about
  one block per call (measured 3663 live over 1000 trips at origin/master, and
  921 with this fix, so it is reduced but not closed here), and it would sit
  inside the very file whose job is to assert a leak count. The reader would
  then be looking at a bound chosen around an unrelated bug.
  bug-a-reading-a-variant-through-an-ansistring-parameter-leaks-after-setlength }
procedure Chk(const w: AnsiString; got: Boolean);
begin
  Inc(total);
  if got then Inc(ok) else WriteLn('FAIL ', w);
end;

{ Survivors across grow / shrink / regrow: the retain half. }
procedure Survivor;
var a: array of TR; j: Integer;
begin
  SetLength(a, 4);
  for j := 0 to 3 do
  begin
    a[j].v := 'variant-payload-long-enough-to-be-heap-' + Chr(48 + j);
    a[j].s := 'string-payload-long-enough-to-be-heap-' + Chr(48 + j);
  end;
  SetLength(a, 8);
  Chk('grow survivor v', a[1].v = 'variant-payload-long-enough-to-be-heap-1');
  SetLength(a, 2);
  Chk('shrink survivor v', a[1].v = 'variant-payload-long-enough-to-be-heap-1');
  SetLength(a, 5);
  Chk('regrow survivor v', a[1].v = 'variant-payload-long-enough-to-be-heap-1');
  Chk('regrow survivor s', a[1].s = 'string-payload-long-enough-to-be-heap-1');
end;

{ Build and drop: the release half. Asserts nothing itself -- the Makefile's
  assert_no_leak row is what reads it, because every check above passes on a
  build that leaks. }
procedure Dropped;
var a: array of TR; j: Integer;
begin
  SetLength(a, 8);
  for j := 0 to 7 do
  begin
    a[j].v := 'dropped-variant-payload-long-enough-' + Chr(48 + j);
    a[j].s := 'dropped-string-payload-long-enough-' + Chr(48 + j);
  end;
end;

var i: Integer;
begin
  ok := 0; total := 0;
  for i := 1 to 1000 do
  begin
    Survivor;
    Dropped;
  end;
  WriteLn('record-variant-member ', ok, '/', total);
end.

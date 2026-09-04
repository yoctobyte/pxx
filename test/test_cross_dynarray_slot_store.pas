program test_cross_dynarray_slot_store;

{ IR_STORE_DYN -- the ARC-correct whole-dyn-array store into a slot ADDRESS
  (a record field, or a nested row), as opposed to IR_STORE_SYM's whole-symbol
  destination. wasm32 was the last backend without the op and REFUSED any body
  containing one (`statement IR op 60`), so this file is its regression.

  THE ASSERTION CLASS IS THE POINT. The defect the op exists to prevent does
  not corrupt at the moment it happens and does not change any length: a handle
  is published into the slot WITHOUT a retain, and the program is correct right
  up until the other owner goes away. So `Length(...)` is blind to it, and so is
  reading the aliased array immediately -- a just-freed block still holds its
  bytes. The rows below therefore

    1. publish the same handle into two slot-address destinations (a nested row
       and a record field), then
    2. make the nested row's owner RELEASE it (SetLength(m, 0) drops the rows),
       then
    3. ALLOCATE AND DIRTY a block of the same shape, so a freed block that gets
       reused reads back as the new owner's data rather than as stale bytes,
    4. and only then assert the ORIGINAL VALUES through both surviving owners.

  Step 3 is not decoration. With it removed the whole test passes on a compiler
  with no retain at all, because nothing has overwritten the freed span yet --
  the same reason `an uninitialised read is usually correct`.

  ALL SEVEN TARGETS RUN IT, and xtensa is the reason step 3 is written down
  rather than assumed. xtensa was this test's own positive control: it was the
  one backend ir.inc still refused to emit the op for, and it printed

      DYNSLOTSTORE FAIL
        r        111 222 333        { the bait's values, read through r }
        rec.rows 111 222 333

  -- the freed block handed straight back to the next SetLength. That is a
  control drawn from the population the question is about, and it is what
  proves these rows can fail at all. It also found the defect: xtensa's backend
  arm for the op had been complete since `3a1c1dc73` and unreachable ever
  since, because the guard that skipped it lives in ir.inc, not in the backend.
  With the guard gone, xtensa prints OK like the rest, and this file no longer
  has a target that demonstrates the failure -- so if you change the assertion
  here, re-check it against a compiler with the retain removed. }

var
  m: array of array of Integer;
  q: array of Integer;
  r: array of Integer;
  ok: Boolean;

type
  TRec = record rows: array of Integer; end;

var
  rec: TRec;

begin
  SetLength(r, 3);
  r[0] := 7; r[1] := 8; r[2] := 9;

  SetLength(m, 2);
  m[0] := r;        { nested row slot   -> IR_STORE_DYN }
  rec.rows := r;    { record field slot -> IR_STORE_DYN }

  ok := (m[0][0] = 7) and (m[0][2] = 9) and (rec.rows[1] = 8);

  { Row 0's owner lets go entirely. `SetLength(m, 0)` is deliberate and the
    first draft of this test had the wrong call: `SetLength(m, 3, 5)` GROWS the
    existing rows in place and preserves their prefixes, so it never releases
    row 0 at all -- m[0][0] read back as 7, and the step meant to drop an owner
    dropped nothing. Measured, not reasoned: the native oracle printed
    `m 3 5 7`. Every retain taken above is what keeps r's block alive now. }
  SetLength(m, 0);
  ok := ok and (Length(m) = 0);

  { Reuse bait, same element count as r's block. }
  SetLength(q, 3);
  q[0] := 111; q[1] := 222; q[2] := 333;

  ok := ok and (r[0] = 7) and (r[1] = 8) and (r[2] = 9);
  ok := ok and (rec.rows[0] = 7) and (rec.rows[1] = 8) and (rec.rows[2] = 9);
  ok := ok and (q[0] = 111) and (q[2] = 333);

  if ok then WriteLn('DYNSLOTSTORE OK')
  else
  begin
    WriteLn('DYNSLOTSTORE FAIL');
    WriteLn('  r        ', r[0], ' ', r[1], ' ', r[2]);
    WriteLn('  rec.rows ', rec.rows[0], ' ', rec.rows[1], ' ', rec.rows[2]);
    WriteLn('  q        ', q[0], ' ', q[1], ' ', q[2]);
    WriteLn('  m        ', Length(m));
  end;
end.

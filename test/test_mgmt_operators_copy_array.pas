program test_mgmt_operators_copy_array;
{ A whole STATIC-ARRAY assignment and the element's `class operator Copy`.

  THE SECOND SITE, AND A SECOND MECHANISM. `d := s` is one block copy: it never
  enters the per-element assign path, so the element's OWN Copy is skipped even
  though nothing about the element is nested. That is why the two controls in
  the ticket both fired throughout while this row did not — `two := one` proves
  the operator is dispatchable, `d[0] := s[0]` proves the per-element path
  reaches it. Both are repeated here so the fixture carries its own evidence
  that a red row means the ARRAY path and not a missing overload.

  TR.Copy ASSIGNS `id` AND DELIBERATELY LEAVES `pad` ALONE, for
  test_mgmt_operators_copy_contained's reason: an operator that dutifully copies
  its fields is indistinguishable from no operator, because the bulk copy moves
  the same bytes. `pad` is the discriminating column and it does not collide —
  the destination's own number survives when the operator ran.

  The operator also prints dst ON ENTRY, because each element is DELEGATED
  ENTIRELY rather than bulk-copied and then notified. Measured under fpc 3.2.2:
  `dst.id-on-entry` is the destination's, not the source's.

  FIVE ROWS, and they are five different lowering paths:
    array of TR   the element declares Copy itself
    array of TH   the element merely CONTAINS a Copy field (gaps + hole, per
                  element)
    rec.arr := other.arr   the FIELD arm, whose sibling is the variable arm
                  above it; the record's other fields must NOT move
    rec := other  a record with a static-array field of TR — the record walk
                  descends through fixed arrays, so this one was already correct
                  before the array arms existed and is here as the control that
                  says so
    d[0] := r     a whole-ROW store into `array of TRow` — the third block-copy
                  arm, reached through a pointer because `d[0][0]` is refused
                  today for an unrelated reason

  NOT HERE: an array whose element mixes an ARC field with an operator field.
  That is refused and keeps today's answer, the named residual on
  bug-a-a-whole-record-assignment-does-not-run-a-contained-fields-copy-operator.
  Nor the UNROLL CAP: over REC_COPY_UNROLL_MAX operator calls the copy falls
  back to the byte copy with a warning, and the Makefile asserts that warning
  rather than this program, because the fallback's OUTPUT is the defect. }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TR = record
    id: Integer;
    pad: Integer;
    class operator Copy(constref src: TR; var dst: TR);
  end;
  { no operator of its own; it CONTAINS one }
  TH = record
    lead: Integer;
    f: TR;
    k: Integer;
  end;
  TW = record
    arr: array[0..1] of TR;
    tail: Integer;
  end;
  TRow = array[0..1] of TR;
  PRow = ^TRow;

class operator TR.Copy(constref src: TR; var dst: TR);
begin
  writeln('  Copy src.id=', src.id, ' dst.id-on-entry=', dst.id,
          ' dst.pad-on-entry=', dst.pad);
  dst.id := src.id;
end;

procedure Controls;
var one, two: TR;
    s, d: array[0..1] of TR;
begin
  one.id := 1; one.pad := 111;
  two.id := 7; two.pad := 777;
  writeln('-- control: two := one');
  two := one;
  s[0].id := 1; s[0].pad := 111;
  d[0].id := 7; d[0].pad := 777;
  writeln('-- control: d[0] := s[0]');
  d[0] := s[0];
end;

procedure OwnCopyElem;
var s, d: array[0..1] of TR;
begin
  s[0].id := 1; s[0].pad := 111; s[1].id := 2; s[1].pad := 222;
  d[0].id := 7; d[0].pad := 777; d[1].id := 8; d[1].pad := 888;
  writeln('-- array of TR: d := s');
  d := s;
  writeln('   [0].id=', d[0].id, ' [0].pad=', d[0].pad,
          ' [1].id=', d[1].id, ' [1].pad=', d[1].pad);
end;

procedure ContainedElem;
var s, d: array[0..1] of TH;
begin
  s[0].lead := 10; s[0].f.id := 1; s[0].f.pad := 111; s[0].k := 20;
  s[1].lead := 30; s[1].f.id := 2; s[1].f.pad := 222; s[1].k := 40;
  d[0].lead := 70; d[0].f.id := 7; d[0].f.pad := 777; d[0].k := 80;
  d[1].lead := 90; d[1].f.id := 8; d[1].f.pad := 888; d[1].k := 99;
  writeln('-- array of TH: d := s');
  d := s;
  writeln('   [0] lead=', d[0].lead, ' f.id=', d[0].f.id, ' f.pad=', d[0].f.pad, ' k=', d[0].k);
  writeln('   [1] lead=', d[1].lead, ' f.id=', d[1].f.id, ' f.pad=', d[1].f.pad, ' k=', d[1].k);
end;

procedure ArrayField;
var a, b: TW;
begin
  a.arr[0].id := 1; a.arr[0].pad := 111;
  a.arr[1].id := 2; a.arr[1].pad := 222;
  a.tail := 5;
  b.arr[0].id := 7; b.arr[0].pad := 777;
  b.arr[1].id := 8; b.arr[1].pad := 888;
  b.tail := 9;
  writeln('-- field: b.arr := a.arr');
  b.arr := a.arr;
  writeln('   [0].id=', b.arr[0].id, ' [0].pad=', b.arr[0].pad,
          ' [1].id=', b.arr[1].id, ' [1].pad=', b.arr[1].pad, ' tail=', b.tail);
end;

procedure WholeRecordWithArrayField;
var a, b: TW;
begin
  a.arr[0].id := 1; a.arr[0].pad := 111;
  a.arr[1].id := 2; a.arr[1].pad := 222;
  a.tail := 5;
  b.arr[0].id := 7; b.arr[0].pad := 777;
  b.arr[1].id := 8; b.arr[1].pad := 888;
  b.tail := 9;
  writeln('-- whole record: b := a');
  b := a;
  writeln('   [0].id=', b.arr[0].id, ' [0].pad=', b.arr[0].pad,
          ' [1].id=', b.arr[1].id, ' [1].pad=', b.arr[1].pad, ' tail=', b.tail);
end;

procedure RowStore;
{ The THIRD block-copy arm: a whole-ROW store into a dynamic array of a
  static-array type. Not the variable arm and not the field arm, so neither of
  the rows above reaches it.

  THE POINTER IS NOT DECORATION. `d[0][0].id` is refused today with `TR has no
  default indexed property` -- a separate gap, not this ticket's -- so the row
  has to be reached through its address. Written this way deliberately rather
  than dropped, because the arm diverged from fpc and a fixture that cannot
  express the shape leaves it unpinned. }
var d: array of TRow;
    r: TRow;
    p: PRow;
begin
  SetLength(d, 2);
  p := @d[0];
  p^[0].id := 7; p^[0].pad := 777;
  p^[1].id := 8; p^[1].pad := 888;
  r[0].id := 1; r[0].pad := 111;
  r[1].id := 2; r[1].pad := 222;
  writeln('-- row store: d[0] := r');
  d[0] := r;
  writeln('   [0].id=', p^[0].id, ' [0].pad=', p^[0].pad,
          ' [1].id=', p^[1].id, ' [1].pad=', p^[1].pad);
end;

begin
  Controls;
  OwnCopyElem;
  ContainedElem;
  ArrayField;
  WholeRecordWithArrayField;
  RowStore;
  writeln('done');
end.

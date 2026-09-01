{ A record whose ONLY managed member is a Variant or a promotable int was not a
  MANAGED RECORD, so nothing walked it.

  RecordHasManagedFieldsDepth2 counted an AnsiString, a dynamic array, a COM
  interface and a nested managed record -- and neither a Variant nor a promo.
  Meanwhile the WALK already knew both: RecordDescMember describes a Variant
  member (kind 5, b2997a31b) and a promo member (kind 7, f806993c8), and
  PXXRecordRetain/Release/ZeroManaged carry arms for each. The descriptor could
  describe these records correctly; the gate said not to emit one.

  WHY THE OBVIOUS PROBE REPORTS SUCCESS. A plain local of record{v:Variant} is
  CLEAN, and so is one in a fixed array, because those are finalized by the
  scope-exit path, which knows a Variant directly. Only a route that goes
  through the RECORD DESCRIPTOR consults this gate. Measured, 1000 trips:

    record{v:Variant}   plain local              2 -> 1      (was already clean)
    record{v:Variant}   fixed array[0..7]        9 -> 3      (was already clean)
    record{v:Variant}   in a dyn array        7708 -> 4      LEAK
    record{p:PromoInt}  in a dyn array        7791 -> 7      LEAK
    record{v:Variant}   nested in a managed rec 936 -> 1     LEAK

  The nested row is the one that shows this is not a dyn-array bug: it is a
  plain local, no array anywhere. The outer record is managed (it has a string),
  so it IS walked, and the walk recursed into an inner record the gate called
  unmanaged. Any container reaching a record through the descriptor was exposed.

  WHY A SECOND MEMBER HID IT. record{v:Variant; s:AnsiString} in a dyn array
  measured clean before the fix, because the AnsiString flipped the gate and
  then the Variant member got described anyway. So the bug needed a record whose
  managed members are ALL of the uncounted kinds -- a shape a probe reaches only
  by deliberately removing the string.

  THE RETAIN HALF IS CHECKED HERE, NOT ASSUMED. Flipping this gate makes copy,
  zero-init and finalization all start acting on these records at once -- the
  one-predicate-answers-three-questions shape that the interface-field history
  in RecordHasManagedFieldsDepth2 records as having gone wrong before. A release
  without a matching retain does not leak, it DESTROYS survivors (9cb079528,
  reverted as a584e8fef). So the survivor and copy rows below matter as much as
  the leak count, and this test is built to run under -dPXX_HEAP_DEBUG.

  Comparisons here are against LITERALS on purpose: comparing a Variant to a
  COMPUTED temporary leaks the temporary (936/1000, unrelated and pre-existing,
  filed separately), which would otherwise redden the leak row for a bug this
  test is not about. }
program test_managed_record_gate_leaks;
type
  TV = record v: Variant; end;
  TP = record p: PromoInt; end;
  TNest = record inner: TV; s: AnsiString; end;
var ok, tot: Integer;

procedure Chk(const w: AnsiString; got: Boolean);
begin Inc(tot); if got then Inc(ok) else WriteLn('FAIL ', w); end;

function PS(const q: PromoInt): AnsiString;
var t: PromoInt;
begin t := q; PS := PXXPromoToStr(@t); end;

{ dyn array of a variant-only record: the 7708 row, survivors across resize }
procedure VarDyn;
var a: array of TV; j: Integer;
begin
  SetLength(a, 4);
  for j := 0 to 3 do a[j].v := 'variant-only-record-payload-heap-1';
  SetLength(a, 8); Chk('v grow',   a[1].v = 'variant-only-record-payload-heap-1');
  SetLength(a, 2); Chk('v shrink', a[1].v = 'variant-only-record-payload-heap-1');
  SetLength(a, 5); Chk('v regrow', a[1].v = 'variant-only-record-payload-heap-1');
  SetLength(a, 0);
end;

{ dyn array of a promo-only record: the 7791 row }
procedure PromoDyn;
var a: array of TP; j: Integer;
begin
  SetLength(a, 4);
  for j := 0 to 3 do begin a[j].p := 1; a[j].p := a[j].p * 100000000000000000000; end;
  SetLength(a, 8); Chk('p grow',   PS(a[1].p) = '100000000000000000000');
  SetLength(a, 2); Chk('p shrink', PS(a[1].p) = '100000000000000000000');
  SetLength(a, 5); Chk('p regrow', PS(a[1].p) = '100000000000000000000');
  SetLength(a, 0);
end;

{ variant-only record NESTED in a managed record: the 936 row, no array }
procedure Nested;
var w: TNest;
begin
  w.inner.v := 'nested-variant-payload-heap-1';
  w.s := 'outer-string-member-payload-heap-1';
  Chk('nested value', w.inner.v = 'nested-variant-payload-heap-1');
end;

{ a copy must RETAIN, or two records share one payload and one free kills both }
procedure Copies;
var r, q: TV; s, t: TP;
begin
  r.v := 'copied-variant-payload-heap-1';
  q := r;
  Chk('copy variant', q.v = 'copied-variant-payload-heap-1');
  s.p := 1; s.p := s.p * 100000000000000000000;
  t := s;
  Chk('copy promo', PS(t.p) = '100000000000000000000');
end;

var i: Integer;
begin
  ok := 0; tot := 0;
  for i := 1 to 1000 do begin VarDyn; PromoDyn; Nested; Copies; end;
  WriteLn('managed-record-gate ', ok, '/', tot);
end.

{ A FIXED ARRAY of Variant or of promotable int, as a record or class MEMBER.

  The member predicates carried `and not UFldIsArray[fi]` on their Variant and
  promo arms, so such a field never became a descriptor member. The chain that
  would have described it needed nothing new: a fixed array lands on the
  matching scalar arm and `arrCount` beside it carries the length, which is
  exactly how a fixed array of AnsiString has always been walked. Only the
  membership test excluded it.

  Measured, 1000 trips, `record ARR; s: AnsiString`, live blocks:

    array[0..3] of Variant, plain local        3799 -> 3
    array[0..3] of PromoInt, plain local       3860 -> 8
    array[0..3] of Variant, in a dyn array    11398 -> 10
    array[0..3] of PromoInt, in a dyn array   11110 -> 10

  The largest of this family, and the last one open.

  BOTH OBVIOUS PROBES REPORT SUCCESS, which is why it outlived three other
  fixes to the same descriptor. The array as its OWN local is clean, and so is
  the record when the array is its ONLY member. It takes a SECOND managed member
  -- the AnsiString above -- because that is what makes the record managed, and
  becoming managed switches finalization from direct field-by-field scope exit
  to the descriptor walk. The walk then drops whatever it cannot describe.

  SO THE DIRECTION IS THE OPPOSITE OF THE GATE BUG. In a544cab70 a record was
  not managed ENOUGH and nothing walked it; here a record becomes managed and
  LOSES the per-field finalization it had been relying on. One predicate decides
  who is DESCRIBED, another decides whether anything is WALKED, and a member can
  fall through either. That is why the gate fix did not close this and why the
  scalar arms did not either.

  Dynamic arrays are deliberately NOT routed through the widened test: a dyn
  array is already a member via FieldIsManaged, gets kind 2, and takes its
  element kind from ManagedElemKind through the dyn descriptor. Counting it
  again would describe one field twice. The member_dynarr rows measured clean
  before and after this change, which is the control for that.

  The survivor and copy rows below are the retain half, checked rather than
  assumed: describing a member makes the walk RELEASE it, and a release without
  a matching retain does not leak, it destroys survivors (9cb079528, reverted as
  a584e8fef). Comparisons are against LITERALS because comparing a Variant to a
  computed temporary leaks the temporary, which is a separate open bug. }
program test_managed_member_array_leaks;
type
  TVA = record va: array[0..3] of Variant; s: AnsiString; end;
  TPA = record pa: array[0..3] of PromoInt; s: AnsiString; end;
  TCV = class public va: array[0..3] of Variant; s: AnsiString; end;
var ok, tot: Integer;

procedure Chk(const w: AnsiString; got: Boolean);
begin Inc(tot); if got then Inc(ok) else WriteLn('FAIL ', w); end;

function PS(const q: PromoInt): AnsiString;
var t: PromoInt;
begin t := q; PS := PXXPromoToStr(@t); end;

procedure FillV(var r: TVA);
var j: Integer;
begin
  for j := 0 to 3 do r.va[j] := 'variant-array-member-payload-heap-1';
  r.s := 'second-managed-member-payload-heap-1';
end;

procedure FillP(var r: TPA);
var j: Integer;
begin
  for j := 0 to 3 do begin r.pa[j] := 1; r.pa[j] := r.pa[j] * 100000000000000000000; end;
  r.s := 'second-managed-member-payload-heap-1';
end;

{ plain locals: the 3799 / 3860 rows }
procedure Locals;
var rv: TVA; rp: TPA;
begin
  FillV(rv); FillP(rp);
  Chk('local variant elem', rv.va[2] = 'variant-array-member-payload-heap-1');
  Chk('local promo elem',   PS(rp.pa[2]) = '100000000000000000000');
end;

{ dyn array of those records, with resize: the 11398 / 11110 rows plus survivors }
procedure Dyn;
var av: array of TVA; ap: array of TPA; j: Integer;
begin
  SetLength(av, 3); SetLength(ap, 3);
  for j := 0 to 2 do begin FillV(av[j]); FillP(ap[j]); end;
  SetLength(av, 6); SetLength(ap, 6);
  Chk('grow variant survivor', av[1].va[2] = 'variant-array-member-payload-heap-1');
  Chk('grow promo survivor',   PS(ap[1].pa[2]) = '100000000000000000000');
  SetLength(av, 2); SetLength(ap, 2);
  Chk('shrink variant survivor', av[1].va[2] = 'variant-array-member-payload-heap-1');
  Chk('shrink promo survivor',   PS(ap[1].pa[2]) = '100000000000000000000');
  SetLength(av, 0); SetLength(ap, 0);
end;

{ a copy must RETAIN every element, not just the first }
procedure Copies;
var a, b: TVA; c, d: TPA;
begin
  FillV(a); b := a;
  Chk('copy variant elem 0', b.va[0] = 'variant-array-member-payload-heap-1');
  Chk('copy variant elem 3', b.va[3] = 'variant-array-member-payload-heap-1');
  FillP(c); d := c;
  Chk('copy promo elem 3', PS(d.pa[3]) = '100000000000000000000');
end;

{ the same array member on a CLASS, whose descriptor is a separate writer }
procedure ClassMember;
var o: TCV; j: Integer;
begin
  o := TCV.Create;
  for j := 0 to 3 do o.va[j] := 'variant-array-member-payload-heap-1';
  o.s := 'second-managed-member-payload-heap-1';
  Chk('class variant elem', o.va[3] = 'variant-array-member-payload-heap-1');
  o.Free;
end;

var i: Integer;
begin
  ok := 0; tot := 0;
  for i := 1 to 1000 do begin Locals; Dyn; Copies; ClassMember; end;
  WriteLn('managed-member-array ', ok, '/', tot);
end.

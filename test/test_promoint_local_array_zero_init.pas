{ A LOCAL `array[0..N] of PromoInt64` is not zero-initialised AT ALL.

    procedure P;
    var a: array[0..3] of promoint64;
    begin
      { ...a[0] is cleared at scope exit from whatever the frame held }
    end;

  This is the THIRD arm of ManagedLocalZeroBytes (pasparser_expr.inc) to ship
  without asking IsArray, after interfaces and Variants. Its AnsiString arm
  multiplies by ArrLen; its Variant arm was fixed to; the promo-int arm still
  says `not IsArray`, so an ARRAY of promo ints gets zeroBytes = 0 — not one
  element's worth, as the Variant bug had, but NONE.

  Two asymmetries, one root, and neither side asks IsArray:

    init     ManagedLocalZeroBytes  zeroes 0 bytes for the whole array
    cleanup  EmitManagedLocalCleanup (symtab.inc) calls PXXPromoClear on the
             slot ADDRESS, i.e. element 0 only

  So element 0 is CLEARED FROM GARBAGE at scope exit. PXXPromoClear tests the
  tag word and, when it reads PROMO_TAG_HEAP (1), releases the payload as a
  managed string — its own header says it "cannot be used on uninitialised
  memory" for exactly this reason. Stack bytes that happen to read {1, <a
  pointer>} therefore free a block the slot never owned. And elements 1..N,
  which cleanup never visits, leak a heap-tier payload instead: the same
  missing IsArray produces a free-too-much at one end and a free-too-little at
  the other.

  The `not IsArray` guard was left in place deliberately when the Variant arm
  was fixed, because no reachable case could be constructed at the time. It IS
  reachable: `promoint64` is a spellable Pascal type name
  (pasparser_decl.inc:543), so this is an ordinary Pascal program.

  Measured with PXXDBG=a.mlzero, which reports the table's own answer:

    sym=zzscalar tk=28 isarray=FALSE          -> 16      { correct }
    sym=zzarr    tk=28 ARRAY len=4 promoint   -> 0       { the hole }
    sym=zzstr    tk=23 isarray=TRUE arrlen=4  -> 32      { control: AnsiString asks }

  Like both siblings this is invisible on a clean stack, so the test dirties
  the stack itself with a pattern that looks like a LIVE heap tag — a pattern
  of zeroes would test nothing, since zero is the answer we want.

  bug-a-managedlocalzerobytes-answers-per-kind-and-has-been-wrong-twice }
program test_promoint_local_array_zero_init;
{$mode objfpc}{$H+}

var
  ok, total: Integer;

procedure Check(const what: string; got, want: Int64);
begin
  Inc(total);
  if got = want then
  begin
    Inc(ok);
    WriteLn('ok   ', what);
  end
  else
    WriteLn('FAIL ', what, ' got=', got, ' want=', want);
end;

{ Leave PROMO_TAG_HEAP (1) where the next call's frame will land, with a
  plausible-looking payload behind it. Tag 1 is precisely what makes
  PXXPromoClear treat the next word as a managed string handle. }
procedure DirtyFrame;
var junk: array[0..63] of Int64; i: Integer;
begin
  for i := 0 to 63 do
    if (i and 1) = 0 then junk[i] := 1        { PROMO_TAG_HEAP }
    else junk[i] := $7F0000000000 + i * 8;    { a pointer-shaped payload }
  if junk[0] = -12345 then WriteLn('unreachable');
end;

{ The tag word is the portable observable: a zero-initialised promo slot is
  {tag=0, payload=0}, and the arm's own comment states the tag MUST start
  PROMO_TAG_INLINE (0). }
function SlotTag(p: Pointer): Int64;
begin
  SlotTag := PInt64(p)^;
end;

procedure ProbeFour;
var a: array[0..3] of promoint64;
begin
  Check('a[0] tag starts inline', SlotTag(@a[0]), 0);
  Check('a[1] tag starts inline', SlotTag(@a[1]), 0);
  Check('a[2] tag starts inline', SlotTag(@a[2]), 0);
  Check('a[3] tag starts inline', SlotTag(@a[3]), 0);
end;

{ A longer array: the arm returned a FLAT zero, so the hole is the whole
  declaration and one length proves nothing about another. }
procedure ProbeEight;
var a: array[0..7] of promoint64; i, bad: Integer;
begin
  bad := 0;
  for i := 0 to 7 do
    if SlotTag(@a[i]) <> 0 then Inc(bad);
  Check('all 8 tags start inline', bad, 0);
end;

{ The control: the SCALAR promo local, which the arm does handle. If this ever
  fails the fix broke the case that always worked. }
procedure ProbeScalar;
var s: promoint64;
begin
  Check('scalar tag starts inline', SlotTag(@s), 0);
end;

begin
  ok := 0; total := 0;
  DirtyFrame; ProbeFour;
  DirtyFrame; ProbeEight;
  DirtyFrame; ProbeScalar;
  WriteLn('promoint-array-zero-init ', ok, '/', total);
end.

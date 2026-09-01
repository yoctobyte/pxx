{ A STATIC OR DYNAMIC ARRAY WHOSE ELEMENTS ARE PROMOTABLE INTS OR VARIANTS.

  ManagedElemKind is "what must a container's element walk do for this element
  type", and it is the one place that answer is written down -- nine emit sites
  and four runtime walks ask it. It answered 0 for a promo element and 0 for a
  Variant element, so every walk declined the array and the SCALAR arm below
  them claimed it instead: `lea rdi, [rbp+Offset]` is element ZERO, so scope
  exit released one element and leaked 1..N. Its own header had already named
  Variant as "the obvious next kind"; promo arrived after it was written.

  Three separate faults, one missing fact:

    scope exit        released element 0, leaked 1..N
    unwind            no landing pad at all, because SymNeedsManagedCleanup
                      asks ManagedElemKind too, so an exception past such a
                      proc leaked every element including 0
    b := a (promo)    reached the scalar promo STORE arm and emitted ONE
                      PXXPromoCopy on the base address: element 0 copied, 1..N
                      left holding the destination's old values, silently

  Measured before the fix, 200k calls with an 8-element local array, against
  the same program using a SCALAR of the same type as the control:

      scalar PromoInt (control)      392 KB
      array[0..7] of PromoInt      87.5 MB
      array[0..7] of Variant          109 MB

  and 392 KB for all three after. The Makefile row asserts an RSS ceiling as
  well as this output, because every assertion below passes on a build that
  leaks -- correctness and reclamation are different claims and the loud one
  hides the quiet one.

  WHY THE CHURN. Retain and release were added in the SAME change on purpose: a
  release without its retain turns SetLength shrink from a leak into a double
  free, which is strictly worse than the bug. A double free is not visible on
  the first pass -- it needs the heap to hand the block out again -- so every
  assertion runs 3000 times rather than once. The churn is also what guards the
  PROMO_TAG_HEAP constant that builtinheap.pas has to repeat from promocore.pas
  (a builtin unit cannot use another one): a tag that matched too often would
  decref an inline payload as a string handle and crash here.

  WHY `PromoInt` AND NOT `promoint64`. The numbered spelling does not exist on
  a 32-bit target -- the compiler refuses it by name there -- and the portable
  one is what lets this file run on all four qemu targets. That is not
  cosmetic: PromoInt is an 8-byte slot on the 32-bit targets and 16 on the
  64-bit ones, and the element STRIDE is the one thing the new element kind
  cannot infer from the kind alone. A file that could only be built for x86-64
  would never have exercised the half of ManagedElemRef that exists for it.

  bug-a-a-static-array-of-promo-ints-releases-only-element-zero }
program test_promoint_array_cleanup;
{$mode objfpc}{$H+}

var
  ok, total: Integer;

procedure Chk(const w: string; const got, want: AnsiString);
begin
  Inc(total);
  if got = want then Inc(ok)
  else WriteLn('FAIL ', w, ' got=', got, ' want=', want);
end;

function PS(const p: PromoInt): AnsiString;
var t: PromoInt;
begin
  t := p;
  PS := PXXPromoToStr(@t);
end;

{ SetLength grow, shrink and regrow on a dynamic array of promo ints: a
  survivor must keep its heap-tier payload (the retain half) and a dropped
  element must be released exactly once. }
procedure DynPromo;
var a: array of PromoInt; i: Integer;
begin
  SetLength(a, 4);
  for i := 0 to 3 do
  begin
    a[i] := 1;
    a[i] := a[i] * 100000000000000000000;
    a[i] := a[i] + i;
  end;
  SetLength(a, 8);
  Chk('dyn promo grow [0]', PS(a[0]), '100000000000000000000');
  Chk('dyn promo grow [3]', PS(a[3]), '100000000000000000003');
  SetLength(a, 2);
  Chk('dyn promo shrink [1]', PS(a[1]), '100000000000000000001');
  SetLength(a, 5);
  Chk('dyn promo regrow [1]', PS(a[1]), '100000000000000000001');
end;

procedure DynVariant;
var v: array of Variant; i: Integer;
begin
  SetLength(v, 4);
  for i := 0 to 3 do
    v[i] := 'payload-' + Chr(65 + i) + '-long-enough-to-be-heap-allocated';
  SetLength(v, 8);
  Chk('dyn variant grow [0]', v[0], 'payload-A-long-enough-to-be-heap-allocated');
  SetLength(v, 2);
  Chk('dyn variant shrink [1]', v[1], 'payload-B-long-enough-to-be-heap-allocated');
  SetLength(v, 6);
  Chk('dyn variant regrow [1]', v[1], 'payload-B-long-enough-to-be-heap-allocated');
end;

{ Whole-array assignment. The promo rows are the ones that were silently
  copying element 0 alone; the AnsiString row is the CONTROL, the element kind
  that has always worked, so a failure here means the shared copy path broke
  rather than the new kind. }
procedure CopyStatic;
var a, b: array[0..3] of PromoInt;
    s, t: array[0..3] of AnsiString;
    i: Integer;
begin
  for i := 0 to 3 do
  begin
    a[i] := 1;
    a[i] := a[i] * 100000000000000000000;
    a[i] := a[i] + i;
  end;
  for i := 0 to 3 do
  begin
    b[i] := 5;
    b[i] := b[i] * 100000000000000000000;
  end;
  b := a;
  Chk('static promo copy [0]', PS(b[0]), '100000000000000000000');
  Chk('static promo copy [3]', PS(b[3]), '100000000000000000003');
  Chk('static promo source intact', PS(a[2]), '100000000000000000002');
  for i := 0 to 3 do s[i] := 'src' + Chr(48 + i);
  for i := 0 to 3 do t[i] := 'dst';
  t := s;
  Chk('CONTROL string copy [2]', t[2], 'src2');
end;

procedure CopyVariant;
var a, b: array[0..3] of Variant; i: Integer;
begin
  for i := 0 to 3 do a[i] := 'src-' + Chr(65 + i) + '-long-enough-to-be-heap-allocated';
  for i := 0 to 3 do b[i] := 'dst-' + Chr(65 + i) + '-long-enough-to-be-heap-allocated';
  b := a;
  Chk('static variant copy [2]', b[2], 'src-C-long-enough-to-be-heap-allocated');
  Chk('static variant source intact', a[2], 'src-C-long-enough-to-be-heap-allocated');
end;

{ The reclamation half. This is what the RSS ceiling in the Makefile row reads:
  every assertion above passes on a build that never frees anything. Each call
  fills eight heap-tier elements and drops them at scope exit. }
procedure LeakPromo;
var a: array[0..7] of PromoInt; i: Integer;
begin
  for i := 0 to 7 do
  begin
    a[i] := 1;
    a[i] := a[i] * 100000000000000000000;
  end;
end;

procedure LeakVariant;
var v: array[0..7] of Variant; i: Integer;
begin
  for i := 0 to 7 do
    v[i] := 'a payload long enough to be heap allocated ' + Chr(65 + i);
end;

var k: Integer;
begin
  ok := 0; total := 0;
  for k := 1 to 3000 do
  begin
    DynPromo;
    DynVariant;
    CopyStatic;
    CopyVariant;
  end;
  for k := 1 to 50000 do
  begin
    LeakPromo;
    LeakVariant;
  end;
  WriteLn('promoint-array-cleanup ', ok, '/', total);
end.

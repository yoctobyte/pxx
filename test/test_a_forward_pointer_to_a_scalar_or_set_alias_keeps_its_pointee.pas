{ `PT = ^TT` written ABOVE `TT = ...`, where TT is an alias to something that has
  no record of its own: a set, a Double, an Int64, a `string[N]`.

  ResolvePendingPointerAliases had four arms -- class/record, named array,
  pointer-to-pointer, and "a plain non-pointer type alias" -- and the last one
  was guarded on `AliasElemRec[target] <> REC_NONE`, which is a RECORD-only
  condition wearing a general name. A scalar or set pointee failed it, took no
  arm at all, and kept the tyInteger that the PtrElemDepth hatch stands in for a
  name it cannot see yet. Measured 2026-09-06 against fpc 3.2.2: SizeOf through
  such a pointer answered 4 for pointees of 8, 11 and 32 bytes, `cGreen in p^`
  over a forward `^TSet` SEGFAULTED, and a store through a forward `^string[4]`
  wrote TEN characters into it.

  EVERY ROW'S CORRECT ANSWER IS DELIBERATELY NOT 4, because 4 is what the defect
  produces AND it is sizeof(Integer) AND it is the storage size of an enum -- so
  a `^TMyInt` or `^TEnum` row answers correctly while the machinery does nothing,
  and cannot tell the two apart. Hence Int64 rather than LongInt, a value above
  2^32 rather than a small one, a 72-member enum whose set is 32 bytes rather
  than a two-member one, and a set member at index 40 rather than index 1.

  THE IN-ORDER TWINS ARE THE CONTROL. Every forward row has one, because a
  declaration order changing whether a program is right is the tell this defect
  class announces itself with, and it is the tell two earlier arms of this same
  procedure were found by. Without the twin, a row is just a program that works.

  .expected is fpc 3.2.2's own output. }
program test_a_forward_pointer_to_a_scalar_or_set_alias_keeps_its_pointee;
{$mode objfpc}

type
  { --- the FORWARD spellings: the pointer above its pointee --- }
  PDbl  = ^TDbl;
  PI64  = ^TI64;
  PSet  = ^TSet;
  PStr  = ^TStr;
  PRec  = ^TRec;              { the arm that already worked, kept as a control }

  TDbl  = Double;
  TI64  = Int64;
  TCol  = (c00,c01,c02,c03,c04,c05,c06,c07,c08,c09,c10,c11,c12,c13,c14,c15,
           c16,c17,c18,c19,c20,c21,c22,c23,c24,c25,c26,c27,c28,c29,c30,c31,
           c32,c33,c34,c35,c36,c37,c38,c39,c40,c41,c42,c43,c44,c45,c46,c47,
           c48,c49,c50,c51,c52,c53,c54,c55,c56,c57,c58,c59,c60,c61,c62,c63,
           c64,c65,c66,c67,c68,c69,c70,c71);
  TSet  = set of TCol;
  TStr  = string[4];
  TRec  = record a, b, c: Double; end;

  { --- and the IN-ORDER twins: the pointee above its pointer --- }
  QDbl2 = Double;
  QI642 = Int64;
  QSet2 = set of TCol;
  QStr2 = string[4];

  PDbl2 = ^QDbl2;
  PI642 = ^QI642;
  PSet2 = ^QSet2;
  PStr2 = ^QStr2;

var
  d: TDbl;   pd: PDbl;    d2: QDbl2;  pd2: PDbl2;
  n: TI64;   pn: PI64;    n2: QI642;  pn2: PI642;
  s: TSet;   ps: PSet;    s2: QSet2;  ps2: PSet2;
  t: TStr;   pt: PStr;    t2: QStr2;  pt2: PStr2;
  r: TRec;   pr: PRec;

begin
  writeln('dbl  size ', SizeOf(d),  ' ', SizeOf(pd^),  ' | ', SizeOf(d2), ' ', SizeOf(pd2^));
  writeln('i64  size ', SizeOf(n),  ' ', SizeOf(pn^),  ' | ', SizeOf(n2), ' ', SizeOf(pn2^));
  writeln('set  size ', SizeOf(s),  ' ', SizeOf(ps^),  ' | ', SizeOf(s2), ' ', SizeOf(ps2^));
  writeln('rec  size ', SizeOf(r),  ' ', SizeOf(pr^));

  { a value that does not fit in the 4 bytes the blank pointee would have moved }
  pd := @d;   pd^  := 1234567.5;
  pd2 := @d2; pd2^ := 7654321.5;
  writeln('dbl  val ', d:0:1, ' | ', d2:0:1);

  pn := @n;   pn^  := 8589934592;      { 2^33 }
  pn2 := @n2; pn2^ := 4294967297;      { 2^32 + 1 }
  writeln('i64  val ', n, ' | ', n2);

  { a member at index 40: past the first word, so a 4-byte set loses it }
  ps := @s;   ps^  := [c40, c02];
  ps2 := @s2; ps2^ := [c71, c03];
  writeln('set  in  ', (c40 in ps^), ' ', (c02 in ps^), ' ', (c39 in ps^),
          ' | ', (c71 in ps2^), ' ', (c03 in ps2^), ' ', (c70 in ps2^));

  { the store through the pointer must clamp to the pointee's OWN capacity }
  pt := @t;   pt^  := 'abcdefghij';
  pt2 := @t2; pt2^ := 'klmnopqrst';
  writeln('str  clamp [', t, '] ', Length(t), ' | [', t2, '] ', Length(t2));

  pr := @r;   pr^.a := 11.5; pr^.b := 22.5; pr^.c := 33.5;
  writeln('rec  val ', r.a:0:1, ' ', r.b:0:1, ' ', r.c:0:1);
end.

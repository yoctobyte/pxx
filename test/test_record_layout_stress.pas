program test_record_layout_stress;

{$PACKRECORDS 8}
type
  TInnerDefault = record
    c: Char;
    b: Boolean;
    w: Word;
    i: Int64;
    tail: Byte;
  end;

  TPackedInner = packed record
    c: Char;
    i: Int64;
    b: Boolean;
    w: Word;
  end;

{$PACKRECORDS 2}
  TCapped2 = record
    c: Char;
    i: Int64;
    w: Word;
    b: Boolean;
  end;

{$PACKRECORDS 1}
  TCapped1 = record
    c: Char;
    i: Int64;
    w: Word;
    b: Boolean;
  end;

{$PACKRECORDS 8}
  TOuterDefault = record
    tag: Byte;
    inner: TCapped2;
    pk: TPackedInner;
    d: Double;
    flag: Boolean;
  end;

  TPackedOuter = packed record
    tag: Byte;
    inner: TInnerDefault;
    tiny: TPackedInner;
    b: Boolean;
    i: Int64;
  end;

var
  id: TInnerDefault;
  pi: TPackedInner;
  c2: TCapped2;
  c1: TCapped1;
  od: TOuterDefault;
  po: TPackedOuter;
  aod: array[0..1] of TOuterDefault;
  apo: array[0..1] of TPackedOuter;

procedure Check(n: Integer; ok: Boolean);
begin
  if ok then writeln(n) else writeln(-n);
end;

begin
  { Pascal Boolean is byte-sized in this dialect; single-bit booleans are a C
    bit-field concern, covered by cstruct_layout_stress_b134.c. }
  Check(1, SizeOf(Boolean) = 1);

  Check(2, SizeOf(TInnerDefault) = 24);
  Check(3, Int64(@id.b) - Int64(@id) = 1);
  Check(4, Int64(@id.w) - Int64(@id) = 2);
  Check(5, Int64(@id.i) - Int64(@id) = 8);
  Check(6, Int64(@id.tail) - Int64(@id) = 16);

  Check(7, SizeOf(TPackedInner) = 12);
  Check(8, Int64(@pi.i) - Int64(@pi) = 1);
  Check(9, Int64(@pi.b) - Int64(@pi) = 9);
  Check(10, Int64(@pi.w) - Int64(@pi) = 10);

  Check(11, SizeOf(TCapped2) = 14);
  Check(12, Int64(@c2.i) - Int64(@c2) = 2);
  Check(13, Int64(@c2.w) - Int64(@c2) = 10);
  Check(14, Int64(@c2.b) - Int64(@c2) = 12);

  Check(15, SizeOf(TCapped1) = 12);
  Check(16, Int64(@c1.i) - Int64(@c1) = 1);
  Check(17, Int64(@c1.w) - Int64(@c1) = 9);
  Check(18, Int64(@c1.b) - Int64(@c1) = 11);

  Check(19, SizeOf(TOuterDefault) = 48);
  Check(20, Int64(@od.inner) - Int64(@od) = 2);
  Check(21, Int64(@od.pk) - Int64(@od) = 16);
  Check(22, Int64(@od.d) - Int64(@od) = 32);
  Check(23, Int64(@od.flag) - Int64(@od) = 40);
  Check(24, Int64(@aod[1]) - Int64(@aod[0]) = 48);

  Check(25, SizeOf(TPackedOuter) = 46);
  Check(26, Int64(@po.inner) - Int64(@po) = 1);
  Check(27, Int64(@po.tiny) - Int64(@po) = 25);
  Check(28, Int64(@po.b) - Int64(@po) = 37);
  Check(29, Int64(@po.i) - Int64(@po) = 38);
  Check(30, Int64(@apo[1]) - Int64(@apo[0]) = 46);

  od.tag := 3;
  od.inner.i := 10000000000;
  od.inner.w := 21;
  od.inner.b := True;
  od.pk.i := 7;
  od.flag := False;
  po.tag := 4;
  po.inner.tail := 5;
  po.tiny.i := 6;
  po.tiny.b := True;
  po.i := 8;

  Check(31, od.inner.i = 10000000000);
  Check(32, od.inner.w + od.pk.w = 21);
  Check(33, od.inner.b and (not od.flag));
  Check(34, po.inner.tail + po.tiny.i + po.i = 19);
  Check(35, po.tiny.b);
end.

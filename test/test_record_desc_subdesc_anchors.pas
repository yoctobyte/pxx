{ The two SELF-RELATIVE anchors in the record layout descriptor, exercised
  together with a leak assertion.

  The format is written down at REC_DESC_HDR_SIZE in compiler/defs.inc. Two of
  its fields are offsets relative to the slot that holds them rather than to the
  blob:

    a kind-3 (nested managed record) member's TypeRef  -> memberPtr + 12
    a kind-2 member whose baseKind is 3, its BaseTypeRef -> dynDescOff + 16

  Both constants stay put across any change to the descriptor's HEADER, and that
  is precisely the property nothing asserted: the header size appears in twelve
  offset expressions across the writer (compiler/rtti_emit.inc) and the reader
  (compiler/builtin/builtinheap.pas), and moving the wrong one of them shifts an
  anchor. The existing record-descriptor rows in this suite cover a variant
  member and a promo member; neither reaches a nested record or a dyn array OF
  records, so neither reads either anchor.

  WHAT THE ASSERTIONS CAN AND CANNOT SEE. The two counts below are the value
  check and they are NOT the guard: a wrong anchor walks garbage on the way OUT
  of a scope, long after every string has been read, so the program prints
  1000/1000 either way. Verified 2026-09-07 by emitting MemberCount as zero
  behind an env gate -- the counts were byte-identical and the census went from
  live=8 to live=9392. The leak row is the one that reads the descriptor at all.

  Nothing here needs an oracle: the counts are 1000 by construction. }
program test_record_desc_subdesc_anchors;

type
  TInner = record
    a: AnsiString;
    b: AnsiString;
  end;
  TOuter = record          { a kind-3 member }
    n: Integer;
    inner: TInner;
    s: AnsiString;
  end;
  TDynRec = record         { a kind-2 member whose baseKind is 3 }
    n: Integer;
    d: array of TInner;
  end;

var
  i, j: Integer;
  live: Integer;

{ A heap-allocating stand-in for IntToStr, so the fixture pulls in no unit. }
function Tag(k: Integer): AnsiString;
var r: AnsiString; n: Integer;
begin
  r := '';
  n := k;
  repeat
    r := Chr(48 + (n mod 10)) + r;
    n := n div 10;
  until n = 0;
  Tag := 'tag-' + r;
end;

procedure UseOuter(k: Integer);
var o: TOuter;
begin
  o.n := k;
  o.inner.a := 'inner-a-' + Tag(k);
  o.inner.b := 'inner-b-' + Tag(k);
  o.s := 'outer-' + Tag(k);
  if Length(o.inner.a) + Length(o.inner.b) + Length(o.s) > 0 then Inc(live);
end;

procedure UseDyn(k: Integer);
var r: TDynRec;
    t: Integer;
begin
  r.n := k;
  SetLength(r.d, 3);
  for t := 0 to 2 do
  begin
    r.d[t].a := 'da-' + Tag(k) + '-' + Tag(t);
    r.d[t].b := 'db-' + Tag(k) + '-' + Tag(t);
  end;
  if Length(r.d[2].b) > 0 then Inc(live);
end;

begin
  live := 0;
  for i := 1 to 1000 do UseOuter(i);
  j := live;
  live := 0;
  for i := 1 to 1000 do UseDyn(i);
  WriteLn('nested-record ', j);
  WriteLn('dyn-of-record ', live);
end.

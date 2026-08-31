program test_pointer_to_dynamic_array_indexing;
{ `p^[i]` where p points at a named DYNAMIC array type.

  The FIXED-array sibling of this was fixed by
  bug-a-indexing-through-a-pointer-to-an-array-is-wrong-for-several-element-kinds.
  Both of the arms that fix landed in guarded on `not ArrTypeIsDyn`, so the
  dynamic half kept the old behaviour: the alias recorded a tyInteger pointee
  and every variable of it inherited a 4-BYTE STRIDE whatever its real element
  was. bug-a-a-pointer-to-a-dynamic-array-indexes-with-a-4-byte-stride

  Four faces, all measured on the pre-fix compiler:
    - Double  elements: p^[i] := 1.5 stored the low 4 bytes of the double, so
      every slot read back 0.00. Compiles clean, exits 0.
    - Int64   elements: writes at stride 4 packed two values into one slot --
      10 and 20 came back as 85899345930 = (20 shl 32) or 10.
    - a pointer-to-dyn-array PARAMETER SEGFAULTED, because the arm that records
      the pointee's dyn depth lived in AllocVar alone.
    - an AnsiString element was refused: "cannot assign ShortString to Char",
      the selector chain having taken the managed-string arm.

  EVERY row compares the pointer spelling against the DIRECT `a[i]` spelling of
  the same access, because the broken rows exited 0 -- a self-consistent wrong
  answer is what this whole family looks like from outside.

  Note on the oracle: FPC REJECTS the bare `p^[i]` spelling ("Illegal
  qualifier") and needs `(p^)[i]`. The parenthesised form was diffed against
  FPC 3.2.2 separately and agrees; this file asserts the two spellings against
  each other and against direct indexing, which is the check FPC cannot do for
  us here. Both spellings are exercised on purpose: they took different paths,
  and for a while `(p^)[i]` was right on the line above a wrong `p^[i]`. }
{$mode objfpc}{$H+}
type
  TDI  = array of Integer;     TPDI  = ^TDI;
  TDI64= array of Int64;       TPDI64= ^TDI64;
  TDD  = array of Double;      TPDD  = ^TDD;
  TDS  = array of AnsiString;  TPDS  = ^TDS;

var ok: Integer;

procedure Chk(const what: AnsiString; got, want: Int64);
begin
  if got = want then Inc(ok)
  else WriteLn('FAIL ', what, ': got ', got, ' want ', want);
end;

procedure ChkS(const what, got, want: AnsiString);
begin
  if got = want then Inc(ok)
  else WriteLn('FAIL ', what, ': got [', got, '] want [', want, ']');
end;

{ A pointer-to-dyn-array PARAMETER: its own allocator, and the face that
  segfaulted rather than answering wrongly. }
procedure FillViaParam(p: TPDD);
var i: Integer;
begin
  for i := 0 to 3 do p^[i] := (i + 1) * 1.5;
end;

procedure Run;
var
  ai: TDI; pi_: TPDI;
  a64: TDI64; p64: TPDI64;
  ad: TDD; pd: TPDD;
  asx: TDS; ps: TPDS;
  i: Integer;
begin
  { Integer elements -- the one kind that was right by coincidence, because the
    wrong stride happened to equal SizeOf(Integer). Kept as the control. }
  SetLength(ai, 4); pi_ := @ai;
  for i := 0 to 3 do pi_^[i] := (i + 1) * 10;
  for i := 0 to 3 do Chk('int p^[i]', pi_^[i], ai[i]);
  Chk('int elem 3', ai[3], 40);

  { Int64 -- stride 4 packed two writes into one 8-byte slot. }
  SetLength(a64, 4); p64 := @a64;
  for i := 0 to 3 do p64^[i] := (i + 1) * 10;
  for i := 0 to 3 do Chk('i64 p^[i]', p64^[i], a64[i]);
  Chk('i64 elem 0', a64[0], 10);
  Chk('i64 elem 1', a64[1], 20);
  Chk('i64 elem 3', a64[3], 40);

  { Double -- the store was 4 bytes wide, so the low half of the double landed
    and every slot read back 0. Compared as bit patterns via a scaled integer so
    the row cannot pass on a formatting accident. }
  SetLength(ad, 4); pd := @ad;
  for i := 0 to 3 do pd^[i] := (i + 1) * 1.5;
  for i := 0 to 3 do Chk('dbl p^[i]', Round(pd^[i] * 100), Round(ad[i] * 100));
  Chk('dbl elem 0', Round(ad[0] * 100), 150);
  Chk('dbl elem 3', Round(ad[3] * 100), 600);

  { The PARENTHESISED spelling, which reached the same place by another path and
    was correct while the bare one was not. }
  for i := 0 to 3 do ad[i] := 0;
  for i := 0 to 3 do (pd^)[i] := (i + 1) * 1.5;
  Chk('dbl (p^)[i] elem 0', Round(ad[0] * 100), 150);
  Chk('dbl (p^)[i] elem 3', Round(ad[3] * 100), 600);

  { The parameter face: segfaulted before. }
  for i := 0 to 3 do ad[i] := 0;
  FillViaParam(@ad);
  Chk('param p^[i] elem 0', Round(ad[0] * 100), 150);
  Chk('param p^[i] elem 3', Round(ad[3] * 100), 600);

  { AnsiString elements -- refused outright before, as "cannot assign
    ShortString to Char": the selector chain read p^ as a string, not as an
    array of strings. }
  SetLength(asx, 3); ps := @asx;
  ps^[0] := 'alpha'; ps^[1] := 'beta'; ps^[2] := 'gamma';
  for i := 0 to 2 do ChkS('str p^[i]', ps^[i], asx[i]);
  ChkS('str elem 0', asx[0], 'alpha');
  ChkS('str elem 2', asx[2], 'gamma');
  Chk('str len 1', Length(ps^[1]), 4);

  { Length through the pointer still answers the array's count, not 1 --
    the earlier face of this same family (bug-p-length-of-a-pointer-to-a-
    dynamic-array-answers-one), asserted here so a stride fix cannot undo it. }
  Chk('Length(pd^)', Length(pd^), 4);
  Chk('Length(ps^)', Length(ps^), 3);
end;

begin
  ok := 0;
  Run;
  WriteLn('PTR TO DYN ARRAY OK checks=', ok);
end.

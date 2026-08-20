{ A record or class FIELD that is a 1-D static array must index from its own
  LOW BOUND. It indexed from the raw index instead, because a 1-D field array's
  low bound was never recorded anywhere -- only 2-D-and-up fields filled the
  dimension table.

  Every non-zero low bound was therefore wrong, and wrong by writing OUTSIDE the
  field:

    array[1..3]   one element past its extent -- into the NEXT field
    array[5..7]   five past -- off the end of the record entirely (SIGSEGV)
    array[-2..2]  two BEFORE it, and on a CLASS that is the object header, so
                  the instance was corrupted and Free crashed

  Reads shifted exactly as the writes did, so the field always looked
  self-consistent and only its NEIGHBOURS were wrong. That is how it survived a
  corpus full of `array[1..N]` fields: nothing reads the neighbour and the
  array's own values check out.

  Guards on both sides of each array are the actual assertion; the array's own
  values are asserted too, because a fix that shifts reads and writes together
  again would keep them right. Every expected value is `fpc -O- -Mobjfpc`'s.
  bug-p-record-field-array-with-a-non-zero-low-bound-writes-out-of-bounds }
program test_record_field_array_low_bound;
{$mode objfpc}{$H+}

type
  TNamed = array[1..3] of Integer;
  TR1 = record g1: Byte;    c: array[1..3] of Byte;    g2: Byte; end;
  TR5 = record g1: Byte;    c: array[5..7] of Byte;    g2: Byte; end;
  TRN = record g1: Byte;    c: array[-2..2] of Byte;   g2: Byte; end;
  TR0 = record g1: Byte;    c: array[0..2] of Byte;    g2: Byte; end;
  TRI = record g1: Integer; c: array[1..3] of Integer; g2: Integer; end;
  TRT = record g1: Integer; c: TNamed;                 g2: Integer; end;
  TR2 = record g1: Byte;    m: array[-1..1, -2..0] of Byte; g2: Byte; end;
  TC  = class  g1: Byte;    c: array[-2..2] of Byte;   g2: Byte; end;

var
  r1: TR1; r5: TR5; rn: TRN; r0: TR0; ri: TRI; rt: TRT; r2: TR2; o: TC;
  ok, total, i, j: Integer;
  pb: ^Byte;

procedure Chk(const what: string; got, want: Integer);
begin
  total := total + 1;
  if got = want then ok := ok + 1
  else writeln('FAIL ', what, ': got ', got, ' want ', want);
end;

begin
  ok := 0; total := 0;

  { low = 1 }
  r1.g1 := 200; r1.g2 := 201;
  for i := 1 to 3 do r1.c[i] := 10 + i;
  for i := 1 to 3 do Chk('r1', r1.c[i], 10 + i);
  Chk('r1.g1', r1.g1, 200);  Chk('r1.g2', r1.g2, 201);
  pb := @r1.c[1];
  for i := 0 to 2 do Chk('r1mem', pb[i], 11 + i);

  { low = 5 -- five elements past the field is off the record: this SIGSEGVed }
  r5.g1 := 100; r5.g2 := 101;
  for i := 5 to 7 do r5.c[i] := 20 + i;
  for i := 5 to 7 do Chk('r5', r5.c[i], 20 + i);
  Chk('r5.g1', r5.g1, 100);  Chk('r5.g2', r5.g2, 101);

  { negative low }
  rn.g1 := 50; rn.g2 := 51;
  for i := -2 to 2 do rn.c[i] := 30 + i;
  for i := -2 to 2 do Chk('rn', rn.c[i], 30 + i);
  Chk('rn.g1', rn.g1, 50);   Chk('rn.g2', rn.g2, 51);

  { low = 0 -- the case that always worked, asserted so a fix cannot break it }
  r0.g1 := 60; r0.g2 := 61;
  for i := 0 to 2 do r0.c[i] := 40 + i;
  for i := 0 to 2 do Chk('r0', r0.c[i], 40 + i);
  Chk('r0.g1', r0.g1, 60);   Chk('r0.g2', r0.g2, 61);

  { a wider element, and CONSTANT indices (the same path, folded) }
  ri.g1 := 300; ri.g2 := 301;
  ri.c[1] := 71; ri.c[2] := 72; ri.c[3] := 73;
  Chk('ri1', ri.c[1], 71);  Chk('ri2', ri.c[2], 72);  Chk('ri3', ri.c[3], 73);
  Chk('ri.g1', ri.g1, 300); Chk('ri.g2', ri.g2, 301);

  { the field declared through a NAMED array type }
  rt.g1 := 400; rt.g2 := 401;
  for i := 1 to 3 do rt.c[i] := 80 + i;
  for i := 1 to 3 do Chk('rt', rt.c[i], 80 + i);
  Chk('rt.g1', rt.g1, 400); Chk('rt.g2', rt.g2, 401);

  { 2-D with negative lows already subtracted its bounds -- the arm that was
    right, kept honest here }
  r2.g1 := 90; r2.g2 := 91;
  for i := -1 to 1 do for j := -2 to 0 do r2.m[i, j] := (i + 2) * 10 + (j + 3);
  for i := -1 to 1 do for j := -2 to 0 do Chk('r2', r2.m[i, j], (i + 2) * 10 + (j + 3));
  Chk('r2.g1', r2.g1, 90);  Chk('r2.g2', r2.g2, 91);

  { a CLASS field: the bytes before it are the object's own header }
  o := TC.Create;
  o.g1 := 70; o.g2 := 71;
  for i := -2 to 2 do o.c[i] := 55 + i;
  for i := -2 to 2 do Chk('cls', o.c[i], 55 + i);
  Chk('cls.g1', o.g1, 70);  Chk('cls.g2', o.g2, 71);
  o.Free;   { crashed: the writes had gone through the instance header }

  writeln('total ok ', ok, ' / ', total);
end.

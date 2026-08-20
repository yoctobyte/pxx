{ test/test_sizeof_array_field.pas
  SizeOf(<record-or-class ARRAY field>) must report the ARRAY's size, not its
  ELEMENT's.

  SizeOf's hand-rolled selector walk sized the final field as
  TypeSize(RecFieldType(...)), and RecFieldType answers an array field's ELEMENT
  kind (UFldTk holds the element type). So `SizeOf(r.A)` on an
  `array[0..2] of Integer` field returned 4 while the SAME array declared as a
  plain var returned 12 -- with no diagnostic, and with the code comment there
  claiming array fields were rejected. The idiomatic uses are
  `Move(src.A, dst.A, SizeOf(src.A))` and `FillChar(r.A, SizeOf(r.A), 0)`, both
  of which then touched one element of three while every surrounding line read
  as correct: the plausible-wrong-value failure mode, not a crash
  (bug-p-sizeof-an-array-field-returns-the-element-size).

  Every expected value below is fpc 3.2.2's answer for the same source. The
  array cases are each asserted AGAINST the plain-var form of the same type, so
  the test states the actual invariant (a field sizes like a variable) rather
  than freezing a number.
}
program test_sizeof_array_field;
{$mode objfpc}{$H+}
type
  TKind = (kA, kB, kC, kD);
  TPt = record X, Y: Integer; end;
  TR = record
    A: array[0..2] of Integer;      { 12 }
    M: array[0..1, 0..3] of Integer;{ 32 }
    K: array[TKind] of Byte;        { 4  }
    D: array of Integer;            { handle }
    P: array[0..1] of TPt;          { 16 }
    S: string[7];                   { 8  }
    C: Char;                        { 1  }
    N: TPt;                         { 8  }
  end;
  TC = class public
    A: array[0..2] of Integer;
    M: array[0..1, 0..3] of Integer;
    D: array of Integer;
    P: array[0..1] of TPt;
    N: TPt;
    procedure SelfChecks;
  end;
  TOuter = record Q: TR; end;

var
  ok, total: Integer;
  r: TR; c: TC; o: TOuter;
  vA: array[0..2] of Integer;
  vM: array[0..1, 0..3] of Integer;
  vK: array[TKind] of Byte;
  vP: array[0..1] of TPt;
  vD: array of Integer;

procedure Check(const nm: string; got, want: Integer);
begin
  total := total + 1;
  if got = want then
  begin
    ok := ok + 1;
    WriteLn('ok   ', nm, ' = ', got);
  end
  else
    WriteLn('FAIL ', nm, ' = ', got, ' want ', want);
end;

procedure TC.SelfChecks;
begin
  { the same walk from inside a method, where the receiver is Self }
  Check('self.A', SizeOf(Self.A), SizeOf(vA));
  Check('self.M', SizeOf(Self.M), SizeOf(vM));
end;

begin
  ok := 0; total := 0;
  c := TC.Create;

  { --- record fields: each sizes exactly like the same type as a variable --- }
  Check('rec.A  1-D', SizeOf(r.A), SizeOf(vA));
  Check('rec.M  2-D', SizeOf(r.M), SizeOf(vM));
  Check('rec.K  enum-indexed', SizeOf(r.K), SizeOf(vK));
  Check('rec.P  array of record', SizeOf(r.P), SizeOf(vP));
  { a dynamic-array field is a HANDLE, so pointer width -- not the element's }
  Check('rec.D  dynamic', SizeOf(r.D), SizeOf(vD));
  { ...and pinned absolutely, because widening this test is what found the VAR
    side answering -4: elementSize * ArrLen with ArrLen = -1, a NEGATIVE size
    that GetMem/Move would have carried straight into the allocator. The two
    assertions above and below only agree with each other; this one says what
    the answer is. }
  Check('var.D  dynamic', SizeOf(vD), SizeOf(Pointer));

  { --- non-array fields must be unchanged by the fix --- }
  Check('rec.S  shortstring', SizeOf(r.S), 8);
  Check('rec.C  scalar', SizeOf(r.C), 1);
  Check('rec.N  nested record', SizeOf(r.N), SizeOf(TPt));

  { --- class fields take the same path --- }
  Check('cls.A  1-D', SizeOf(c.A), SizeOf(vA));
  Check('cls.M  2-D', SizeOf(c.M), SizeOf(vM));
  Check('cls.P  array of record', SizeOf(c.P), SizeOf(vP));
  Check('cls.D  dynamic', SizeOf(c.D), SizeOf(vD));
  Check('cls.N  nested record', SizeOf(c.N), SizeOf(TPt));

  { --- a deeper chain: the walk must size the LAST field, not the first --- }
  Check('nested.Q.A', SizeOf(o.Q.A), SizeOf(vA));
  Check('nested.Q.N', SizeOf(o.Q.N), SizeOf(TPt));
  Check('nested.Q', SizeOf(o.Q), SizeOf(TR));

  c.SelfChecks;

  { --- the siblings the ticket said to grep for: these were already right,
        and must stay right --- }
  Check('Length(rec.A)', Length(r.A), 3);
  Check('High(rec.A)', High(r.A), 2);
  Check('Length(cls.A)', Length(c.A), 3);

  WriteLn('total ok ', ok, ' / ', total);
end.

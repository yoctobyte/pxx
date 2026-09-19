program test_a_packed_record_field_reads_and_writes_at_any_offset;
{ bug-a-xtensa-unaligned-packed-record-field-access-faults.

  A `packed record` exists to put fields at unaligned offsets -- wire formats,
  file headers, anything whose layout someone else chose. On xtensa the ordinary
  sized load and store FAULT on a misaligned address: not "absorb it slowly" as
  on x86-64, and not "emulated by qemu" as on arm32 and riscv32, but SIGBUS. So
  before the fix, `r.I := n` on a packed record was `qemu: uncaught target
  signal 7 (Bus error)` -- every field wide enough to matter, on the PRIMARY ESP
  target.

  EVERY ROW HERE IS A VALUE, NOT AN OFFSET. What differs legitimately between
  targets is where the fields land; what may not differ is what comes back out
  of them. The cross rows compare against the x86-64 run of this same source.

  THE LAST GROUP IS THE ONE THE NARROW FIX WOULD HAVE MISSED. An offset-by-
  offset rule -- "use byte access when this field's own offset is odd" -- is
  correct for a packed record sitting at an aligned address and wrong for an
  ELEMENT of an array of them: with SizeOf 7, element 1 starts at base+7 and
  then even the offset-0 field is misaligned. That is why the compiler asks
  whether the RECORD is ragged and then treats all of its fields that way,
  rather than asking about one field's offset. Walk the array and every element
  must read back what was written. }

type
  TPk = packed record
    B: Byte;
    I: LongInt;        { offset 1 -- the reported case }
    W: Word;           { offset 5 }
  end;

  TWide = packed record
    Tag: Byte;
    Q: Int64;          { offset 1 }
    D: Double;         { offset 9 }
    S: SmallInt;       { offset 17, signed 16-bit }
    C: ShortInt;       { offset 19, signed 8-bit }
  end;

  TNest = packed record
    Lead: Byte;
    Inner: TPk;        { a ragged record nested inside another }
  end;

  { THE POSITIVE CONTROL FOR THE WALK'S OWN TERMINATION, and it is a compiler
    crash rather than a wrong value, so the row is that this file BUILDS.
    UFldRec_ is populated for a CLASS field as well as for a record one, and a
    class field is a pointer -- `Next: TNode` is ordinary, legal Pascal and
    self-referential, so a raggedness walk keyed on "this field has a record
    id" recurses for ever. It did: 23 of 60 lib/rtl root units segfaulted the
    compiler. The class also HOLDS a ragged record by value, so the walk has a
    real reason to look at its fields rather than bailing on the class early. }
  TNode = class
    Next: TNode;
    Pk: TPk;
  end;

var
  r: TPk;
  w: TWide;
  n: TNest;
  arr: array[0..3] of TPk;
  i: Integer;
  ok: Boolean;
  nd: TNode;

begin
  r.B := 1; r.I := -123456789; r.W := 65535;
  WriteLn('B=', r.B, ' I=', r.I, ' W=', r.W, ' size=', SizeOf(r));

  { read-modify-write through the same field, so a bad load and a bad store
    cannot cancel out into a right-looking answer }
  r.I := r.I + 1;
  WriteLn('after +1 I=', r.I);

  w.Tag := 9;
  w.Q := -1234567890123456789;
  w.D := 2.5;
  w.S := -30000;
  w.C := -100;
  WriteLn('Tag=', w.Tag, ' Q=', w.Q, ' S=', w.S, ' C=', w.C, ' size=', SizeOf(w));
  WriteLn('D=', w.D:0:4);

  { the SIGNED narrow fields are the ones a byte-composed load gets wrong by
    forgetting to sign-extend: an unsigned rebuild makes -30000 into 35536 }
  w.S := w.S + 1;
  w.C := w.C + 1;
  WriteLn('after +1 S=', w.S, ' C=', w.C);

  n.Lead := 7;
  n.Inner.B := 2;
  n.Inner.I := 999999;
  n.Inner.W := 258;
  WriteLn('nested Lead=', n.Lead, ' B=', n.Inner.B, ' I=', n.Inner.I,
          ' W=', n.Inner.W, ' size=', SizeOf(n));

  { THE ARRAY GROUP. Element k starts at k*SizeOf(TPk), so with an odd size
    every element after the first has a different misalignment. }
  for i := 0 to 3 do
  begin
    arr[i].B := i;
    arr[i].I := 1000000 + i;
    arr[i].W := 1000 + i;
  end;
  ok := True;
  for i := 0 to 3 do
    if (arr[i].B <> i) or (arr[i].I <> 1000000 + i) or (arr[i].W <> 1000 + i) then
      ok := False;
  WriteLn('array of packed records round-trips: ', ok);
  WriteLn('element 3 I=', arr[3].I, ' W=', arr[3].W);

  { the self-referential class. Reaching this line at all is the assertion; the
    values are here so the row is not merely a compile check. }
  nd := TNode.Create;
  nd.Next := nil;
  nd.Pk.B := 3;
  nd.Pk.I := -2000000;
  nd.Pk.W := 40000;
  WriteLn('class field B=', nd.Pk.B, ' I=', nd.Pk.I, ' W=', nd.Pk.W,
          ' self-ref nil: ', nd.Next = nil);
  nd.Free;
end.

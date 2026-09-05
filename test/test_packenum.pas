{ {$PACKENUM} behaviour: a narrowed enum must still BE an enum.

  The layout half is test-packenum-gcc-oracle. This half is the part a
  layout-only test cannot see -- narrowing an enum's storage kind moved it off
  tyInteger, and seven separate sites carried the enum's IDENTITY behind a
  `kind = tyInteger` guard that silently stopped firing. Every row below
  printed an ORDINAL rather than a member name at that point, with nothing
  failing and no diagnostic.

  Verified row-for-row against fpc 3.2.2 on x86-64.
  feature-p-packenum-and-h-minus-for-the-fpc-compiler-corpus }
program test_packenum;

{$PACKENUM 1}
type
  TCol = (cRed, cGreen, cBlue);
  TWide = (wA, wB = 300);
  TRec = record a: Byte; c: TCol; w: TWide; b: Byte; end;
{$PACKENUM 4}
type
  TLate = (lA, lB);      { declared AFTER the switch back: must be 4, not 1 }

var r: TRec; c: TCol; s: set of TCol; l: TLate; i: Integer;
begin
  WriteLn('sizes ', SizeOf(TCol), ' ', SizeOf(TWide), ' ', SizeOf(TLate), ' ', SizeOf(TRec));
  c := cGreen;
  WriteLn('name ', c);                  { identity through a VARIABLE }
  WriteLn('ord ', Ord(c));
  WriteLn('cast ', TCol(2));            { identity through a CAST }
  WriteLn('castord ', Ord(TCol(2)));
  c := cBlue;
  WriteLn('cmp ', c > cGreen, ' ', c = cBlue);
  for c := cRed to cBlue do Write('loop ', Ord(c), ' ');
  WriteLn;
  s := [cRed, cBlue];                   { a SET must NOT inherit the member name }
  WriteLn('set ', cRed in s, ' ', cGreen in s);
  r.a := 1; r.c := cBlue; r.w := wB; r.b := 9;
  WriteLn('rec ', r.a, ' ', Ord(r.c), ' ', Ord(r.w), ' ', r.b);
  WriteLn('recname ', r.c);             { identity through a record FIELD }
  l := lB;
  WriteLn('late ', l, ' ', Ord(l));
  i := Ord(cBlue);
  WriteLn('toint ', i);
  WriteLn('lohi ', Ord(Low(TCol)), ' ', Ord(High(TCol)));
end.

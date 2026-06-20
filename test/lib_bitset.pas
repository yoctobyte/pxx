program lib_bitset;
{ Unit test for lib/rtl/bitset. Track B. Build with the pinned stable. }
uses bitset;
var ba: TBitArray; i, n: Integer;
begin
  { Init + SetBit + TestBit }
  BitArrayInit(ba, 128);
  BitArraySetBit(ba, 0);
  BitArraySetBit(ba, 1);
  BitArraySetBit(ba, 31);
  BitArraySetBit(ba, 32);
  BitArraySetBit(ba, 127);
  writeln(BitArrayTestBit(ba, 0));     { TRUE }
  writeln(BitArrayTestBit(ba, 1));     { TRUE }
  writeln(BitArrayTestBit(ba, 2));     { FALSE }
  writeln(BitArrayTestBit(ba, 31));    { TRUE }
  writeln(BitArrayTestBit(ba, 32));    { TRUE }
  writeln(BitArrayTestBit(ba, 33));    { FALSE }
  writeln(BitArrayTestBit(ba, 127));   { TRUE }
  writeln(BitArrayTestBit(ba, 126));   { FALSE }

  { ClearBit }
  BitArrayClearBit(ba, 1);
  writeln(BitArrayTestBit(ba, 1));     { FALSE }
  BitArrayClearBit(ba, 31);
  writeln(BitArrayTestBit(ba, 31));    { FALSE }

  { Toggle }
  BitArrayToggle(ba, 2);              { FALSE -> TRUE }
  writeln(BitArrayTestBit(ba, 2));     { TRUE }
  BitArrayToggle(ba, 2);              { TRUE -> FALSE }
  writeln(BitArrayTestBit(ba, 2));     { FALSE }

  { Count }
  BitArrayInit(ba, 200);
  BitArraySetBit(ba, 0);
  BitArraySetBit(ba, 10);
  BitArraySetBit(ba, 31);
  BitArraySetBit(ba, 32);
  BitArraySetBit(ba, 100);
  BitArraySetBit(ba, 199);
  writeln(BitArrayCount(ba));          { 6 }

  { NextSet — iterate all set bits }
  BitArrayInit(ba, 200);
  BitArraySetBit(ba, 5);
  BitArraySetBit(ba, 10);
  BitArraySetBit(ba, 70);
  BitArraySetBit(ba, 150);
  n := 0;
  i := BitArrayNextSet(ba, 0);
  while i >= 0 do
  begin
    write(i, ' ');
    n := n + 1;
    i := BitArrayNextSet(ba, i + 1);
  end;
  writeln;
  writeln(n);                          { 4 }

  { NextSet from past end }
  writeln(BitArrayNextSet(ba, 200));   { -1 }

  { NextSet starting at a set bit }
  writeln(BitArrayNextSet(ba, 10));    { 10 }

  { NextSet starting just past a set bit }
  writeln(BitArrayNextSet(ba, 11));    { 70 }
end.

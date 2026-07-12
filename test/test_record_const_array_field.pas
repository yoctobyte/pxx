program test_record_const_array_field;
type
  TGuid = record
    D1: LongWord;
    D2: Word;
    D3: Word;
    D4: array[0..7] of Byte;
  end;
const
  G: TGuid = (D1: $20400; D2: 0; D3: 0; D4: ($C0, 0, 0, 0, 0, 0, 0, $46));
begin
  writeln(G.D1, ' ', G.D4[0], ' ', G.D4[7]);
end.

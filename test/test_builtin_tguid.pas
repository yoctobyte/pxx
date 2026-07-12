program test_builtin_tguid;
const G: TGuid = (D1: $20400; D2: 0; D3: 0; D4: ($C0, 0, 0, 0, 0, 0, 0, $46));
begin
  writeln(G.D1, ' ', G.D4[0], ' ', G.D4[7], ' ', SizeOf(TGuid));
end.

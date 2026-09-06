program test_intern_hash_collision;
{ 'aar' and 'ac0' land in the SAME bucket of InternStr's dedup index: djb2
  masked to 24 bits gives 8936569 for both. The index selects a bucket; only the
  full length-then-characters comparison decides identity. If it ever answered
  from the KEY, the second literal would resolve to the first one's pool slot.

  This is not a hypothetical shape. With the comparison deliberately removed and
  the bucket trusted, this program prints `aar aar aar aar` and the first row
  FAILs -- and the compiler built that way cannot even compile itself, dying on
  `EmitAsmX64: unknown 0-operand mnemonic`, because merged literals corrupt the
  mnemonic table first. So the guard has a positive control and it has been run.

  A key must be able to distinguish the things it is used to look up, or the
  thing that reads it must. Here it is the second.
  feature-dynamic-compiler-tables }
var a, b, c, d: string;
begin
  a := 'aar';
  b := 'ac0';
  c := 'aar';   { must dedup to the same entry as a }
  d := 'ac0';   { must dedup to the same entry as b }
  writeln(a, ' ', b, ' ', c, ' ', d);
  if a = b then writeln('FAIL: colliding literals merged') else writeln('ok: distinct');
  if (a <> c) or (b <> d) then writeln('FAIL: dedup lost a literal') else writeln('ok: dedup');
end.

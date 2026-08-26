{ Low/High of an array report the bound in the INDEX's type, not its ordinal.

  `array['a'..'e']` answered 97 and 101; `array[TE]` answered 0 and 2. The
  values were always right -- only the type was missing, because an array's
  index type was never recorded next to its bounds, so by the time Low/High
  folded there was nothing left saying the index had been a Char. Both fold
  sites (the type NAME and the VARIABLE) stamped Integer, and they had to agree,
  so neither could be fixed alone.

  Every row is measured against fpc 3.2.2 (-Mobjfpc -O1). The plain-integer and
  multi-dim rows are pinned too: the fix moves the type-stamping for ALL array
  Low/High folds, so "nothing else changed" needs evidence, not a claim. }
program test_low_high_index_type;
type
  TE  = (eA, eB, eC);
  TC  = array['a'..'e'] of Integer;
  TB  = array[Boolean] of Integer;
  TEA = array[TE] of Integer;
  TI  = array[5..9] of Integer;
  TM  = array[2..4, 7..8] of Integer;
var
  c: TC; b: TB; e: TEA; i: TI; m: TM;
  ch: Char; bo: Boolean; en: TE; n: Integer;
  anon: array['p'..'t'] of Integer;
{ NOT pinned here: `const CLO = Low(TC); WriteLn(CLO)` still prints 97. That is
  not this fix -- pxx's constant evaluator represents every ordinal as a bare
  Int64 by design, so `const X = eB` already prints 1 rather than eB, with no
  Low/High involved. Filed separately as
  bug-p-the-constant-evaluator-erases-an-ordinals-type. }
begin
  { char index, through the variable and through the type name -- these two
    must agree, which is the reason they were both wrong before }
  WriteLn(Low(c), ' ', High(c));
  WriteLn(Low(TC), ' ', High(TC));
  WriteLn(Low(anon), ' ', High(anon));
  { Boolean index }
  WriteLn(Low(b), ' ', High(b));
  WriteLn(Low(TB), ' ', High(TB));
  { enum index: the ordinal was right all along, the enum identity was lost }
  WriteLn(Low(e), ' ', High(e));
  WriteLn(Low(TEA), ' ', High(TEA));
  { an enum TYPE name has the same missing fact }
  WriteLn(Low(TE), ' ', High(TE));
  { ...and an ordinary integer index is untouched }
  WriteLn(Low(i), ' ', High(i));
  WriteLn(Low(TI), ' ', High(TI));
  WriteLn(Low(m), ' ', High(m));
  WriteLn(Low(TM), ' ', High(TM));
  { the point of the whole thing: the natural loop, with a typed loop variable }
  for ch := Low(c) to High(c) do Write(ch); WriteLn;
  for bo := Low(b) to High(b) do Write(bo, ' '); WriteLn;
  for en := Low(e) to High(e) do Write(en, ' '); WriteLn;
  for n := Low(i) to High(i) do Write(n, ' '); WriteLn;
  { the bound still behaves as an ordinal where one is wanted }
  WriteLn(Ord(Low(c)), ' ', Ord(High(c)), ' ', Ord(Low(e)), ' ', Ord(High(e)));
end.

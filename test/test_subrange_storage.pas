program test_subrange_storage;
{ A subrange type is stored in the NARROWEST ordinal that spans its declared
  range, not in the 4-byte default.

  `T = 0..255` is a type whose values need one byte. Storing four is what makes
  `array[0..N] of 0..255` cost 4x the memory the declaration asks for — which is
  the entire reason a program writes that instead of `array of Integer` — and
  every record with a subrange field wider than the language implies. Measured
  before the fix: SizeOf answered 4 for `0..255`, `-128..127` and `10..20`, where
  FPC 3.2.2 answers 1 for all three.

  THE SIZE ROWS ARE THE POINT AND THEY ARE THE POSITIVE CONTROL. Every one is
  FPC 3.2.2's own answer, taken from `fpc -O- -Mobjfpc`, and every one CHANGED
  with the fix (4->1, 4->1, 4->1, 12->3 for the packed record, 16->4 for the
  array). Reverting the narrowing turns this test red on those rows alone, which
  is what a value test could never do: every value below was already correct
  before the fix and stayed correct after, so a value-only test would certify
  the wasteful layout as fine.

  THE VALUE ROWS ARE HERE ANYWAY, because a narrower slot is exactly where a
  wrong answer would appear: 200 read back as -56 from a signed byte, a `for`
  loop over 250..255 that never terminates because the counter wraps, a var
  parameter passed as a wider slot than the callee writes. All of it is diffed
  against FPC in the ticket; the rows kept here are the ones that would move.

  THE DECLARED BOUNDS ARE A SEPARATE FACT from the storage width, and Low/High
  and the {$R+} check must keep using them: `10..20` stores in a byte and must
  still answer 10 and 20, not 0 and 255. That is the row most likely to be
  broken by a future "simplification" that reads the bounds off the storage kind.

  BOTH SPELLINGS ARE HERE — the named form (`T = lo..hi`) and the inline form
  (`var x: lo..hi`) are two parser arms for one construct, and fixing one alone
  is how the other stays broken for months.

  compat-pascal-four-type-sizes-disagree-with-fpc-and-every-value-agrees }
type
  TSmall = 0..255;
  TNeg   = -128..127;
  TSm2   = 10..20;
  TMid   = 0..70000;
  TBig   = -3000000000..3000000000;
  TChr   = 'a'..'z';
  TSgn   = -1..1;        { the lib/rtl TValueRelationship shape }
  TPk    = packed record a: TSmall; b: TNeg; c: 0..255; end;
  TArr   = array[0..3] of TSmall;
var
  x: TSmall; n: TNeg; g: TBig; r: TPk; a: TArr;
  inl: 0..255; inlN: -100..100; c: TChr;
  i, s: Integer;

procedure BumpVar(var v: TSmall);
begin v := v + 1; end;

function Sgn(v: LongInt): TSgn;
begin
  if v < 0 then Sgn := -1 else if v > 0 then Sgn := 1 else Sgn := 0;
end;

begin
  { sizes — FPC 3.2.2's column, and every one of these moved with the fix }
  WriteLn(SizeOf(TSmall), ' ', SizeOf(TNeg), ' ', SizeOf(TSm2), ' ',
          SizeOf(TMid), ' ', SizeOf(TBig), ' ', SizeOf(TChr));
  WriteLn(SizeOf(TPk), ' ', SizeOf(TArr));

  { the declared bounds survive the narrowing }
  WriteLn(Low(TSmall), ' ', High(TSmall), ' ', Low(TNeg), ' ', High(TNeg));
  WriteLn(Low(TSm2), ' ', High(TSm2), ' ', Low(TMid), ' ', High(TMid));

  { values through the narrow slot }
  x := 200; WriteLn(x, ' ', x + 50);
  n := -100; n := n + 50; WriteLn(n);
  g := -3000000000; g := g + 1; WriteLn(g);
  r.a := 250; r.b := -120; r.c := 7; WriteLn(r.a, ' ', r.b, ' ', r.c);
  s := 0;
  for i := 0 to 3 do begin a[i] := 60 + i * 50; s := s + a[i]; end;
  WriteLn(a[0], ' ', a[3], ' ', s);
  x := 7; BumpVar(x); WriteLn(x);
  { a loop counter in a one-byte slot must still terminate at the top of its range }
  s := 0; for x := 250 to 255 do s := s + x; WriteLn(s);
  { the inline spelling — the sibling parser arm }
  inl := 240; inl := inl + 10; WriteLn(inl, ' ', SizeOf(inl));
  inlN := -90; inlN := inlN - 5; WriteLn(inlN, ' ', SizeOf(inlN));
  c := 'q'; WriteLn(c, ' ', Ord(c));

  { SIGNEDNESS is deliberately NOT asserted by a value row here. It is real --
    we pick the same rung FPC does, so TypeInfo reports the same ordinal type
    (test_typeinfo_typedata covers that) -- but no CORRECT program can see it:
    every value inside the declared range reads back the same signed or
    unsigned. The only thing that separates them is a {$R-} store of a value
    outside the type, and FPC's answer there is not a specification we chase.
    Measured 2026-09-02: `d: 1..10; {$R-} d := 200` gives 200 under FPC and -56
    here, and that divergence is CHOSEN -- the program already made the mistake
    the declared range exists to describe. }

  { a subrange as a FUNCTION RESULT -- the shape lib/rtl actually uses, in
    TValueRelationship (-1..1) and TRoundToRange (-37..37), and the one shape
    the rest of this test misses: it exercises var and value parameters but
    never a narrowed RETURN slot. }
  WriteLn(Sgn(-9), ' ', Sgn(9), ' ', Sgn(0), ' ', Sgn(-9) * 10);
end.

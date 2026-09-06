program t;
{ A named type cast is recognised at two doors -- the user-alias table and the
  builtin scalar-name table -- and a source declaration must outrank a builtin at
  BOTH. The rows below vary the SELECTOR (which door recognises the name), not
  the payload: only the "both" rows can tell the two orders apart, and the
  alias-only / builtin-only rows are the controls that must not move.

  Each row prints the CONST fold beside the RUNTIME cast of the same expression.
  They are two independent evaluators, so a row where they differ is wrong
  without needing an oracle. }
type
  TMyOrd  = Int64;      { alias-only: no builtin of this name }
  LongInt = Int64;      { BOTH: builtin says 4 bytes, the declaration says 8 }
  Word    = ShortInt;   { BOTH, the other direction: builtin 2 unsigned, decl 1 signed }
const
  CAlias = TMyOrd(4294967296 + 5);
  CBoth  = LongInt(4294967296 + 5);
  CNarr  = Word(200);
  CBuilt = Int64(4294967296 + 5);
  CPlain = Cardinal(4294967296 + 5);
var
  a: TMyOrd; b: LongInt; n: Word; i: Int64; c: Cardinal;
begin
  a := TMyOrd(4294967296 + 5);
  b := LongInt(4294967296 + 5);
  n := Word(200);
  i := Int64(4294967296 + 5);
  c := Cardinal(4294967296 + 5);
  WriteLn('alias-only   ', CAlias, ' ', a);
  WriteLn('both-wide    ', CBoth, ' ', b);
  WriteLn('both-narrow  ', CNarr, ' ', n);
  WriteLn('builtin-only ', CBuilt, ' ', i);
  WriteLn('builtin-narr ', CPlain, ' ', c);
end.

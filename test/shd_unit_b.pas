unit shd_unit_b;
{ Scope-hiding fixture B — the twin of shd_unit_a, which declares the SAME six names with
  different content, so `uses shd_unit_b, shd_unit_b` must bind B's of every
  one of them and the reverse order must bind A's — the FPC rule, verified
  against FPC 3.2.2.
  bug-p-scope-hiding-covers-routines-but-not-types-and-classes }
interface

type
  TShdThing = class function W: AnsiString; end;
  TShdAlias = ShortInt;
  TShdEnum = (seOne, seTwo, seThree);
  TShdRec = record x: Integer; tag: Char; extra: Integer; end;
  TShdArr = array[0..7] of Integer;

const
  ShdName = 'CONST-B';

function ShdWho: AnsiString;

implementation

function TShdThing.W: AnsiString; begin W := 'CLASS-B'; end;
function ShdWho: AnsiString; begin ShdWho := 'ROUTINE-B'; end;

end.

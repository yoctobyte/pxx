unit shd_unit_a;
{ Scope-hiding fixture A. Its twin shd_unit_b declares the SAME six names with
  different content, so `uses shd_unit_a, shd_unit_b` must bind B's of every
  one of them and the reverse order must bind A's — the FPC rule, verified
  against FPC 3.2.2.
  bug-p-scope-hiding-covers-routines-but-not-types-and-classes }
interface

type
  TShdThing = class function W: AnsiString; end;
  TShdAlias = LongInt;                    { 4 bytes here, 1 in B }
  TShdEnum = (seOne, seTwo);              { High = 1 here, 2 in B }
  TShdRec = record x: Integer; tag: Char; end;
  TShdArr = array[0..3] of Integer;       { 4 elements here, 8 in B }

const
  ShdName = 'CONST-A';

function ShdWho: AnsiString;

implementation

function TShdThing.W: AnsiString; begin W := 'CLASS-A'; end;
function ShdWho: AnsiString; begin ShdWho := 'ROUTINE-A'; end;

end.

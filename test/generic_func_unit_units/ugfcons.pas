{ Consumer half: a UNIT that inline-specializes ANOTHER unit's generic routine.
  This is the shape the fix's placement is chosen for. Every unit's tokens are
  APPENDED behind the file that used it, so ugfcons' body sits behind ugfprov's
  template in Tokens[] while being ahead of it in scope, and a forward scan from
  the template never reaches it. The sweep runs at the end of ParseUsesClause --
  the one point where "what this clause just imported" is answerable and every
  use of it is still ahead -- which is also where the class-side desugar runs.

  A sweep hung off the PROGRAM instead would leave this row broken: there is no
  later point inside ugfcons from which a forward scan covers its own body. }
unit ugfcons;
{$mode objfpc}

interface

function ConsumerUse: Integer;
function ConsumerUseTry: Integer;

implementation

uses ugfprov;

function ConsumerUse: Integer;
begin
  Result := specialize Twice<Integer>(21);
end;

function ConsumerUseTry: Integer;
begin
  Result := specialize Bump<Integer>(10);
end;

end.

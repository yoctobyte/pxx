unit udefscopechild;
{ bug-p-a-units-define-leaks-into-the-units-it-uses -- the CHILD.

  Every arm here answers a question about a symbol somebody ELSE may or may not
  have defined. Nothing in this unit defines PARENTDEF or CLIDEF; the parent
  that uses this unit defines the first on the command line only the second. }
interface

function SeesParentDefine: AnsiString;
function SeesCommandLineDefine: AnsiString;
function SeesItsOwnDefine: AnsiString;
function ChildRecSize: Integer;

implementation

{$define CHILDONLY}

type
  TChildRec = record a: Byte; b: LongInt; end;

function SeesParentDefine: AnsiString;
begin
{$ifdef PARENTDEF} SeesParentDefine := 'parent-define-LEAKED';
{$else}            SeesParentDefine := 'parent-define-scoped';
{$endif}
end;

function SeesCommandLineDefine: AnsiString;
begin
{$ifdef CLIDEF} SeesCommandLineDefine := 'cli-define-reaches-here';
{$else}         SeesCommandLineDefine := 'cli-define-LOST';
{$endif}
end;

function SeesItsOwnDefine: AnsiString;
begin
{$ifdef CHILDONLY} SeesItsOwnDefine := 'own-define-works';
{$else}            SeesItsOwnDefine := 'own-define-EATEN';
{$endif}
end;

{ The parent sets PACKRECORDS 1. This record is not the parent's business. }
function ChildRecSize: Integer;
begin ChildRecSize := SizeOf(TChildRec); end;

end.

unit udefscopeparent;
{ bug-p-a-units-define-leaks-into-the-units-it-uses -- the PARENT.

  Sets a define and a record-packing mode BEFORE the uses, which is the whole
  point: under FPC neither reaches the used unit, and under pxx both did. }
{$define PARENTDEF}
{$PACKRECORDS 1}
{$R+}
{$Q+}
{$ASSERTIONS OFF}
interface

uses udefscopechild;

function ChildSeesParentDefine: AnsiString;
function ChildSeesCommandLineDefine: AnsiString;
function ChildSeesItsOwnDefine: AnsiString;
function ChildRecordSize: Integer;
function ChildRangeCheck: AnsiString;
function ChildOverflowCheck: AnsiString;
function ChildAssertions: AnsiString;
function ParentRecordSize: Integer;
function ParentStillSeesItsOwnDefine: AnsiString;
function ParentSeesChildDefine: AnsiString;

implementation

type
  TParentRec = record a: Byte; b: LongInt; end;

function ChildSeesParentDefine: AnsiString;
begin ChildSeesParentDefine := SeesParentDefine; end;

function ChildSeesCommandLineDefine: AnsiString;
begin ChildSeesCommandLineDefine := SeesCommandLineDefine; end;

function ChildSeesItsOwnDefine: AnsiString;
begin ChildSeesItsOwnDefine := SeesItsOwnDefine; end;

function ChildRecordSize: Integer;
begin ChildRecordSize := ChildRecSize; end;

function ChildRangeCheck: AnsiString;
begin ChildRangeCheck := RangeCheckLeaked; end;

function ChildOverflowCheck: AnsiString;
begin ChildOverflowCheck := OverflowCheckLeaked; end;

function ChildAssertions: AnsiString;
begin ChildAssertions := AssertionsLeaked; end;

{ ...and the parent's OWN packing must survive its own `uses`. A fix that
  clears state instead of saving and restoring it passes every row above and
  fails this one. }
function ParentRecordSize: Integer;
begin ParentRecordSize := SizeOf(TParentRec); end;

function ParentStillSeesItsOwnDefine: AnsiString;
begin
{$ifdef PARENTDEF} ParentStillSeesItsOwnDefine := 'parent-keeps-its-own';
{$else}            ParentStillSeesItsOwnDefine := 'parent-LOST-its-own';
{$endif}
end;

{ THE REVERSE LEAK. CHILDONLY is defined in the child's implementation; it must
  not be visible here afterwards. }
function ParentSeesChildDefine: AnsiString;
begin
{$ifdef CHILDONLY} ParentSeesChildDefine := 'child-define-LEAKED-UP';
{$else}            ParentSeesChildDefine := 'child-define-scoped';
{$endif}
end;

end.

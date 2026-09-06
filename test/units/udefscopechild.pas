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
function RangeCheckLeaked: AnsiString;
function OverflowCheckLeaked: AnsiString;
function AssertionsLeaked: AnsiString;

implementation

uses sysutils;

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

{ The parent also sets {$R+}, {$Q+} and {$ASSERTIONS OFF}. None of the three is
  this unit's business either, and unlike the ifdef arms these three are visible
  as a RAISE rather than as a different value: a used unit compiled with checks
  it never asked for fails at runtime in code its author read as check-free. }
function RangeCheckLeaked: AnsiString;
var a: array[0..3] of Integer; i, v: Integer;
begin
  RangeCheckLeaked := 'range-check-did-not-leak';
  i := 7;
  try
    v := a[i];
    if v = 12345 then RangeCheckLeaked := 'range-check-did-not-leak';
  except
    on E: Exception do RangeCheckLeaked := 'range-check-LEAKED';
  end;
end;

function OverflowCheckLeaked: AnsiString;
var x, y: LongInt;
begin
  OverflowCheckLeaked := 'overflow-check-did-not-leak';
  x := 2147483647;
  try
    y := x + 1;
    if y = 0 then OverflowCheckLeaked := 'overflow-check-did-not-leak';
  except
    on E: Exception do OverflowCheckLeaked := 'overflow-check-LEAKED';
  end;
end;

{ NOT an fpc-differential row and it cannot be one: fpc defaults assertions OFF
  and pxx defaults them ON, deliberately (see AssertionsVal in defs.inc). So
  this answers 'assert-fires' under a correct pxx and 'assert-silent' under a
  correct fpc, and the LEAK also reads 'assert-silent'. Asserted from a
  pxx-only program; see the Makefile row that names this function. }
function AssertionsLeaked: AnsiString;
begin
  AssertionsLeaked := 'assert-silent';
  try
    Assert(1 = 2, 'the parent turned assertions off, not this unit');
  except
    on E: Exception do AssertionsLeaked := 'assert-fires';
  end;
end;

end.

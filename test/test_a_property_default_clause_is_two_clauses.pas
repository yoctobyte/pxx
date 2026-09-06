program test_a_property_default_clause_is_two_clauses;
{ `default` IS TWO UNRELATED CLAUSES SHARING ONE KEYWORD, and one arm served both.

    property Items[i: Integer]: Integer read GetItem; default;    THE default
                                                                  indexed property
    property Depth: Integer read FDepth write FDepth default 16;  a streaming
                                                                  default VALUE

  Only the first may set the flag. The second set it too, so a class declaring a
  value clause BEFORE a genuine indexed `default;` had the slot STOLEN.

  DECLARATION ORDER IS THE WHOLE TEST. Row B is `t[2]`, and it was refused with
  `default property is write-only` where fpc prints 100 -- but ONLY because Depth
  is declared above Items in this file. Swap those two declarations and both
  compilers print 100, so a test that declares the indexed property first is
  green against the broken compiler. The order here is deliberate and must not be
  tidied.
  bug-p-a-property-default-value-clause-is-read-as-the-default-indexed-property-marker

  ROWS D..H ARE THE VALUE FORMS THAT WERE REFUSED OUTRIGHT: a named constant, a
  constant EXPRESSION, `nodefault`, and `stored`. fpc's own pscanner.pp:893 uses
  `default DefaultMaxIncludeStackDepth`, which is how this was reached. `default
  16` alone appeared to work, and that is the trap -- the class-member loop ends
  in a catch-all `else Next` that silently skips unrecognised tokens, so
  `default 16 77 88 99;` compiled clean, while a NAME took the loop's identifier
  branch and was parsed as a field declaration demanding a ':'. One missing arm;
  which spelling you probe decides whether you see a bug.

  `stored` decides whether a streaming system writes a property out, so its
  consumer is lib/pcl and any .lfm round-trip.
  feature-p-a-property-stored-clause-is-not-supported

  ORACLE: `fpc -Mdelphi` 3.2.2's own output, byte for byte. }
{$mode delphi}

const
  DefaultDepth = 16;

type
  TC = class
  private
    FDepth: Integer;
    FF: Integer;
    function GetItem(i: Integer): Integer;
    function IsStored: Boolean;
  public
    { DECLARED FIRST ON PURPOSE -- see the header }
    property Depth: Integer read FDepth write FDepth default DefaultDepth;
    property Wide: Integer read FDepth write FDepth default DefaultDepth + 1;
    property Plain: Integer read FF write FF nodefault;
    property Kept: Integer read FF write FF stored False;
    property Kept2: Integer read FF write FF stored IsStored;
    property Both: Integer read FF write FF stored False default 3;
    property Items[i: Integer]: Integer read GetItem; default;
  end;

function TC.GetItem(i: Integer): Integer;
begin
  GetItem := 100 + i;
end;

function TC.IsStored: Boolean;
begin
  IsStored := True;
end;

var
  t: TC;
begin
  t := TC.Create;
  t.Depth := 1; t.Plain := 2; t.Kept := 5;
  WriteLn('A ', t.Depth, ' ', t.Plain, ' ', t.Kept);
  WriteLn('B ', t[2]);            { the DEFAULT indexed property, via the subscript }
  WriteLn('C ', t.Items[3]);      { …and named, which never depended on the flag }
  t.Wide := 7; t.Kept2 := 8; t.Both := 9;
  WriteLn('D ', t.Wide, ' ', t.Kept2, ' ', t.Both);
end.

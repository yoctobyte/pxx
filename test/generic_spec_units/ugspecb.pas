unit ugspecb;
{ uses GENERIC first, then non-generic — the ONLY difference from ugspeca. }
{$mode objfpc}
interface

uses
  ugspecgen,
  ugspecnon;

type
  TLongIntTest = specialize TTest<LongInt>;

function MakeB: TLongIntTest;
function PlainB: TTest;

implementation

function MakeB: TLongIntTest;
begin
  MakeB := TLongIntTest.Create;
  MakeB.Val := 22;
end;

function PlainB: TTest;
begin
  PlainB := TTest.Create;
end;

end.

unit ugspeca;
{ uses NON-generic first, then generic. }
{$mode objfpc}
interface

uses
  ugspecnon,
  ugspecgen;

type
  TLongIntTest = specialize TTest<LongInt>;

function MakeA: TLongIntTest;
function PlainA: TTest;

implementation

function MakeA: TLongIntTest;
begin
  MakeA := TLongIntTest.Create;
  MakeA.Val := 11;
end;

function PlainA: TTest;
begin
  PlainA := TTest.Create;
end;

end.

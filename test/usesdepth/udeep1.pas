unit udeep1;
{ Top. Names udeep2 in its IMPLEMENTATION, the other of the two sections. }
interface
function Outer: Integer;
implementation
uses udeep2;
function Outer: Integer;
begin
  Outer := Middle;
end;
end.

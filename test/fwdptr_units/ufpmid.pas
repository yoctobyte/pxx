unit ufpmid;
{ Does nothing but stand between the program and ufpdeep. That is the whole
  point: with only this level of indirection, ufpdeep's types are no longer in
  the PROGRAM's scope, which is the difference the defect turned on. }
interface

uses ufpdeep;

function Deep: Integer;

implementation

function Deep: Integer;
var x: TX; p: PX;
begin
  FillIt(x);
  p := @x;
  Deep := p^.v;
end;

end.

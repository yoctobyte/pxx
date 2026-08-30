unit uerrinst;
{ The INSTANTIATING unit. It specializes uerrtmpl's TBox, which is what forces
  the template's method body to be type-checked.

  This file is padded so that its OWN line 22 is the marker below. The error
  belongs to uerrtmpl.pas:22; if a diagnostic ever names uerrinst.pas:22 it is
  pairing a line number from one file with a filename from another, which is
  the defect this test exists for. }
{$mode objfpc}
interface

uses
  uerrtmpl;

type
  TIntBox = specialize TBox<Integer>;

function MakeBox: TIntBox;

implementation

{ line 22 of uerrinst.pas: NOT the error site, and never was }

function MakeBox: TIntBox;
begin
  MakeBox := TIntBox.Create;
end;

end.

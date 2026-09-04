{ Specializes TBox<Integer> from an IMPLEMENTATION `uses`, and publishes only an
  Integer. The alias row it mints is private to this unit -- correctly, since
  nothing about the specialization is in its interface.

  What made this a regression is what the IMPORTER then could not do. See
  test_generic_implsect_dup.pas. }
unit ugimpb;
{$MODE DELPHI}

interface

function MakeB: Integer;

implementation

uses ugimpa;

function MakeB: Integer;
var b: TBox<Integer>;
begin
  b.V := 202;
  Result := b.V;
end;

end.

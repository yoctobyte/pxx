unit othername_in;
{ Reached through a subdirectory path and used through its QUALIFIED name, which
  is where `in`'s binding is actually observable rather than inferred from a flat
  lookup. feature-p-uses-a-unit-in-an-explicit-file }
interface
function OtherFive(x: Integer): Integer;
implementation
function OtherFive(x: Integer): Integer;
begin
  OtherFive := x * 5;
end;
end.

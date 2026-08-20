unit macronest_fpcmode;
{$MODE OBJFPC}{$H+}
{$MACRO ON}
{ The other half of test_pascal_macro_comment_nesting: an FPC mode, where
  nesting IS on { and an inner comment like this one must be consumed } so the
  outer comment runs to here. A unit and not a second block in the program,
  because FPC allows a mode switch only at the top of a compilation unit -- and
  it therefore also exercises the per-unit reset of the setting, which is the
  thing ExpandPasMacros is seeded from. }
interface

{$define NESTED_TAG := 'fpc-mode-nested'}

function NestedTag: AnsiString;

implementation

function NestedTag: AnsiString;
begin
  Result := NESTED_TAG;
end;

end.

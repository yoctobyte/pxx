program test_pascal_conditional_include;

{$define INCLUDE_OK}
{$if defined(INCLUDE_OK)}
{$include directive_active.inc}
{$else}
{$include missing_inactive_include.inc}
{$endif}

{$ifdef MISSING_INCLUDE}
{$include another_missing_inactive_include.inc}
{$endif}

{$I directive_short.inc}

begin
  writeln(IncludedValue);
  writeln(ShortIncludedValue);
end.

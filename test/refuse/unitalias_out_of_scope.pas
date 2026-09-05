program unitalias_out_of_scope;
{ NEGATIVE CONTROL for the `unitalias` scope. `Scoped.Alias` resolves for units
  under test/libmanifest/, because that tree's pxxlib.cfg declares it. This
  program is in test/, outside that tree, and must NOT be able to spell it —
  otherwise an alias declared by one vendored library would reach every other
  compilation and the scoping claim would be false while every positive row
  still passed. feature-p-resolve-delphi-dotted-unit-scope-names }
uses Scoped.Alias;
begin
  WriteLn(AliasSees);
end.

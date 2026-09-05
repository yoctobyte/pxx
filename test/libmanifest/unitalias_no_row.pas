program unitalias_no_row;
{ NEGATIVE CONTROL for the alias being a TABLE. This file IS inside the manifest
  tree and does see the manifest — the sibling program in test/ does not — but
  the manifest has no row for `Scoped.NoSuchRow`, so it must still fail. A
  "strip any dotted prefix" implementation would resolve this to `nosuchrow`
  and silently bind whatever the search path had, which is the wrong-unit
  failure this feature is written to avoid.
  feature-p-resolve-delphi-dotted-unit-scope-names }
uses Scoped.NoSuchRow;
begin
end.

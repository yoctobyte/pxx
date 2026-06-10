program test_relpath_uses;

{ Path-form unit references:
  - './relpath/sub/relmath' — relative to this file's directory, extension
    inferred; relmath itself pulls '../relstr' relative to its own directory.
  - './relpath/sub/../relext.pas' — explicit extension plus a '..' segment
    that NormalizePath collapses. }
uses './relpath/sub/relmath', './relpath/sub/../relext.pas';

begin
  writeln(AddTwo(3, 4)); { Triple(3)+4 = 13 }
  writeln(Triple(5));    { nested relative unit's symbol = 15 }
  writeln(Hundred);      { 100 }
end.

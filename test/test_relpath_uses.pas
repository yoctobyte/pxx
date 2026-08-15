program test_relpath_uses;

{ Path-form unit references:
  - './relpath/sub/relmath' — relative to this file's directory, extension
    inferred; relmath itself pulls '../relstr' relative to its own directory.
  - './relpath/sub/../relext.pas' — explicit extension plus a '..' segment
    that NormalizePath collapses. }
uses './relpath/sub/relmath', './relpath/sub/../relext.pas', './relpath/relstr';

begin
  writeln(AddTwo(3, 4)); { Triple(3)+4 = 13 }
  { relstr is named HERE as well, on purpose. relmath's own `uses '../relstr'`
    is in relmath's namespace, not ours -- a program does not inherit its
    imports' imports. That nested resolution is still under test, and by the
    line above rather than this one: AddTwo's body calls Triple, so AddTwo(3,4)
    = 13 can only come out right if relmath resolved '../relstr' itself. }
  writeln(Triple(5));    { 15 }
  writeln(Hundred);      { 100 }
end.

program test_cross_loadfile;

{ Cross-target LoadFile oracle (compile with -dPXX_MANAGED_STRING). LoadFile
  reads a whole file into a managed AnsiString via the portable PXXStrLoadFile
  helper. Reads a stable committed fixture so the output is identical on every
  target as on x86-64. Run from the repo root (the Makefile rule does). }

var
  path, contents: AnsiString;
begin
  path := 'test/hello.pas';
  LoadFile(path, contents);
  writeln(contents);
  { reload into the same var: exercises release-of-old + publish-new }
  LoadFile(path, contents);
  writeln(contents);
end.

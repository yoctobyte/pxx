{ SPDX-License-Identifier: 0BSD }
{ A program or library name can be DOTTED, like a unit header and a `uses`
  entry: `program testrunner.rtlgenerics;` opens rtl-generics' test runner, and
  fpc 3.2.2 accepts it. pxx refused it with "expected 'begin' before '.'". The
  optional parameter list after the name still parses. The library sibling is
  test/test_dotted_library_name.pas. }
program testrunner.rtl.generics(input, output);
begin
  writeln('dotted program ok');
end.

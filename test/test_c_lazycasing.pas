program test_c_lazycasing;
{ {$LAZYCASING ON} lets a C-import call resolve through a case-insensitive
  fallback when exactly one external symbol matches, linking to the exact
  declared spelling. The declaration is `add_two`; the calls use other casings.
  A warning is printed (to stdout) per mismatched call, then the program runs. }
{$LAZYCASING ON}
function add_two(a, b: Integer): Integer; cdecl; external 'liblazycasing.so';   { soname only — the loader finds it via LD_LIBRARY_PATH (hermetic, like test_c_argspill) }
begin
  writeln(add_two(3, 4));    { exact case: no warning }
  writeln(ADD_TWO(10, 20));  { upper case: warns, resolves }
  writeln(Add_Two(100, 1));  { mixed case: warns, resolves }
end.

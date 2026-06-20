program test_unitpath;
{ Exercises the Pascal-`uses` search-path slice of
  feature-dynamic-include-paths-config. `platgreet` is NOT in this program's
  directory; it is resolved from a directory supplied on the command line via
  -Fu<dir> or -I<dir>. Compiling with test/unitpath/posix vs test/unitpath/esp
  on the search path selects which backend binds — the PAL mechanism. }
uses platgreet;
begin
  writeln(PlatName);
end.

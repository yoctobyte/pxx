{ A Pascal `uses` binds a Pascal UNIT, whatever a C include root happens to
  contain.

  `-I<dir>` deliberately adds a search root for BOTH `#include` and `uses`
  (feature-dynamic-include-paths-config), and the unit search probed
  `.pas`/`.pp`/`.c`/`.h` in each root BEFORE reaching the compiler-anchored RTL
  directory. `-Ilib/crtl/include` therefore put twenty-seven C headers on the
  Pascal unit path, and four of them share a basename with a real unit:
  math, netdb, strings, and png -- that last one via /usr/include/libpng16,
  which any gtk+-3.0 `pkg-config --cflags` puts on the command line.

  The damage went two ways, and the quiet one is why this file RUNS rather than
  only compiling:

    * LOUD, when the header lacks the symbol: `undefined variable (Floor)`,
      naming the use rather than the flag;
    * SILENT, when the header has it: the reference binds, `ok:` prints, and
      the `uses` becomes a dynamic import -- the binary carries a DT_NEEDED on
      `libmath.so` and dies at load with "error while loading shared
      libraries". A compile-only check passes on that arm, which is the arm
      that shipped.

  `strings` is deliberately NOT exercised here: `test/strings.pas` is a test
  PROGRAM, and a `uses strings` from this directory binds it through the
  source-file-directory probe long before any include root is consulted. That
  probe is a different arm and was left alone on purpose -- a `.c`/`.h` sitting
  next to the file you are compiling is an explicit local choice, where a root
  reached through a flag is not.

  Every value below is FPC 3.2.2's for the same program.
  bug-a-a-c-include-path-captures-a-pascal-uses-and-emits-a-dynamic-import }
program test_uses_beats_a_c_header_on_the_include_path;
uses math, netdb;
var
  n: LongInt;
begin
  { lib/rtl/math.pas, not lib/crtl/include/math.h -- the collision in ordinary
    use, where the symptom is a missing Floor }
  n := Floor(3.7);   writeln(n);
  n := Ceil(3.2);    writeln(n);
  n := Trunc(Power(2.0, 10.0));  writeln(n);

  { lib/rtl/netdb.pas, not lib/crtl/include/netdb.h. Nothing is called: the
    binding is the assertion, and resolving a name would make the test depend
    on the box's network. }
  if @GetHostByName = nil then writeln('netdb nil') else writeln('netdb bound');
end.

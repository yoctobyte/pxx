{ The emitted binary must not depend on HOW THE COMPILER WAS INVOKED.

  A `uses` clause is the whole point of this file: unit resolution is where the
  compiler builds a path out of ExeDir (= the directory of ParamStr(0)), and
  that resolved path used to be interned into the EMITTED string pool. So the
  same compiler, compiling this same source, produced different bytes depending
  on whether it was run from inside the repo (where ExeDir + '../lib/rtl/'
  resolves) or from a copy elsewhere (where it falls back to the CWD-relative
  spelling). A program with no `uses` never noticed.
  bug-a-the-compilers-output-depends-on-argv0

  The assertion lives in the Makefile: compile this twice, from two different
  compiler paths, and cmp. Running it is the cheap half — a compile that emits
  nothing is not the property under test. }
program quick_canary_argv0;
uses sysutils;
begin
  writeln('argv0 canary ok ' + IntToStr(42));
end.

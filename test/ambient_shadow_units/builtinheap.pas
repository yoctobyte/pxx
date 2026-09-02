{ SPDX-License-Identifier: MPL-2.0 }
unit builtinheap;
{ AN IMPOSTOR, and it must never be loaded.

  It shares a directory with prog.pas on purpose. `builtinheap` is a unit the
  COMPILER injects — no source in this directory names it — so binding it to a
  file that merely happens to lie next to the program silently swaps out the
  runtime. Until 2026-09-02 that is exactly what happened: the SourceFileDir
  probe in pasparser_proc.inc ran for compiler-injected units too.

  Emptiness is the assertion. If this unit is loaded, the link has no
  PXXStrFromLit and the compile FAILS; the recipe expects prog to build and
  print. A stale-but-VALID copy is the shape that actually cost a session an
  afternoon — it compiles, and every measurement afterwards reads as "my change
  to the RTL did nothing" — but emptiness is what a test can assert.

  Sibling: test/aintostr_units/builtinheap.pas is an impostor that MUST be
  loaded, through -Fu. That is the difference this pair guards: -Fu is a path
  the user typed, a directory listing is not. }
interface
implementation
end.

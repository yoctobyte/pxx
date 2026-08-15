program uses_tkinter_and_configparser;
{ REGRESSION: `Text` the Tk widget must not capture `Text` the RTL file record
  in a unit that never named tkinter.

  lib/pcl's `Text = class(Widget)` and the RTL's `Text` (the FILE record) share
  a name. FindUClassNonRecord — the "prefer the CLASS over a same-named RECORD"
  predicate, right for a NilPy class position
  (bug-nilpy-text-class-name-binds-the-rtl-file-record) — scanned FLAT and
  GLOBAL, so it answered for lib/rtl/configparser.pas too. configparser's own
  `var f: Text; ... Assign(f, path)` then had a class where a record belonged
  and the program failed to build with

      error: no overload of Assign matches these arguments
        argument types: (class, AnsiString)

  naming configparser, where nothing is wrong. `uses configparser` ALONE
  compiled: naming tkinter somewhere else in the program was the entire
  difference. So any app with a Tk UI and a settings file could not build.

  Compiled, not run — tkinter needs an X display. Lives in examples/tk/ for the
  same reason the other tkinter tests do: a source in test/ resolving `tk`
  picks up test/strings.pas (a PROGRAM named Strings) ahead of the RTL unit
  tk.pas uses, because the resolver searches the source file's own directory
  first.

  bug-a-tkinters-text-class-captures-the-rtl-text-record-in-other-units }
uses tkinter, configparser;
begin
  WriteLn('both ok');
end.

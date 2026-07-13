{ `on E: Exception` must catch an exception class from a LATER-compiled unit (b322).

  The on-clause match enumerates the target's descendants when the handler's own
  unit lowers — so an exception class declared in a unit compiled AFTERWARDS was
  not in the set, and the catch-all `on E: Exception do` silently let it escape.
  fcl-fpcunit's AssertException lost fpjson's EJSON purely because of unit order:
  the whole suite died "Unhandled exception" on a test that deliberately raises.

  A ROOT exception class (no parent, named Exception) now matches unconditionally
  — everything raisable descends from it. The general open-world fix (runtime
  parent-chain walk for non-root targets) is bug-pascal-except-on-class-open-world.

  except_b322_thrower (compiled FIRST, catches Exception) is handed a raiser that
  throws except_b322_late.ELate (compiled LATER via the program's uses tail). }
program test_except_cross_unit_class_b322;
{$mode objfpc}{$h+}
uses except_b322_thrower, except_b322_late;

begin
  { CatchAll lives in the FIRST unit; ELate in the SECOND. }
  CatchAll(@RaiseLate);
  Writeln('after');
end.

program test_mgmt_operators_addref_refused;
{ `class operator AddRef` is RECOGNISED — the spelling is not a syntax error —
  and still REFUSED, because nothing dispatches the event it fires on.

  This fixture was `..._copy_refused` until 2026-09-06 and it EXPIRED the day
  Copy was dispatched: a test whose whole claim is "we do not support X" goes
  red when someone implements X, and the repair is to re-aim it at the part
  still true rather than to delete it.

  What is still true is a measurement, not an arbitrary line. Copy and AddRef
  are NOT two operators competing for one event — measured against fpc 3.2.2
  with three programs differing only in which operators are declared, they fire
  at DISJOINT sites and neither ever displaces the other:

    b := a, arr[i] := a, b := Mk   ->  Copy          (dispatched, see
                                                      test_mgmt_operators_copy)
    a by-VALUE parameter copy      ->  AddRef        (this ticket)
    a const or var parameter       ->  neither

  So AddRef is a different hook in a different pass, not the remaining half of
  the same one. With Copy declared and AddRef absent, fpc runs NO operator at
  all for the by-value copy while still Finalizing the parameter slot at exit.

  feature-pascal-management-operators-copy-and-addref }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    n: Integer;
    class operator AddRef(var a: TFoo);
  end;
class operator TFoo.AddRef(var a: TFoo);
begin a.n := a.n + 1; end;

begin
end.

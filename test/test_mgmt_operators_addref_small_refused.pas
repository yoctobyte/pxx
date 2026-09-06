program test_mgmt_operators_addref_small_refused;
{ A record with a management operator, passed BY VALUE at 8 bytes or less, is
  REFUSED — and this fixture has now been re-aimed twice, which is the point of
  keeping it rather than deleting it.

  It was `..._copy_refused` until 2026-09-06 and expired when Copy was
  dispatched. It became `..._addref_refused` — "AddRef is recognised and nothing
  dispatches it" — and expired the same day when AddRef was dispatched. A test
  whose whole claim is "we do not support X" goes red the moment someone
  implements X, and the repair is to re-aim it at the part still true.

  What is still true, and it is a measured limit rather than an arbitrary line:
  at or under 8 bytes a by-value record argument has NO ADDRESS. The backend
  pushes the record's own bytes as one or two machine words, so the "copy" is
  that push and there is no slot for AddRef to act on or for Finalize to release.

  FORCING A PRIVATE TEMP AT THIS SIZE WAS TRIED AND MEASURED WRONG: the callee
  then receives the temp's address where its ABI says bytes, and the field read
  `callee(byval) id=` printed 4311096 against fpc's 107 — while AddRef and
  Finalize themselves ran correctly on the temp. That is a silently wrong value
  in the callee, which is worse than this refusal, so the refusal stays until
  the argument can be passed as bytes from an addressable copy.

  Over 8 bytes the operators dispatch and match fpc 3.2.2 byte for byte —
  test_mgmt_operators_addref. The two files are the same feature either side of
  one threshold, and the threshold is why this one still exists.

  `const` and `var` are the documented way through at any size: fpc runs NEITHER
  operator for those, so refusing them here would diverge from fpc rather than
  fall short of it.

  feature-pascal-management-operators-copy-and-addref }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    n: Integer;                        { 4 bytes — under the threshold }
    class operator AddRef(var a: TFoo);
  end;
class operator TFoo.AddRef(var a: TFoo);
begin a.n := a.n + 1; end;

procedure TakeVal(f: TFoo);            { by VALUE: this is the refused site }
begin WriteLn(f.n); end;

var a: TFoo;
begin
  a.n := 1;
  TakeVal(a);
end.

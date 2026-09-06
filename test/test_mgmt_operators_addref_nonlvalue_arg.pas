program test_mgmt_operators_addref_nonlvalue_arg;
{ THE SECOND AXIS: the ARGUMENT'S SHAPE, not the parameter's mode.

  test_mgmt_operators_addref varies the parameter mode (by-value / const / var)
  and holds the argument fixed at an LVALUE. That is exactly half the space, and
  the missing half is not decorative -- it is where the first emitter was wrong:

    - A `const` or `var` parameter given a NON-LVALUE (a function result) gets a
      private temp too, purely so the by-ref slot has something to point at. The
      first cut of the AddRef hook keyed on "a temp was built" and so fired
      here, where fpc runs NO operator at all: pxx printed `AddRef sees id=7`
      and the callee read 107 against fpc's 7.
    - A BY-VALUE parameter given a non-lvalue takes the SAME arm, and there fpc
      DOES run AddRef. So the two cases are indistinguishable by the arm and
      need opposite answers; the discriminator is whether `var`/`out`/`const`
      was written, never whether a temp was needed.

  The lvalue rows in the sibling file cannot fail on either of these: no temp is
  built for a const/var lvalue argument, so the arm is never reached. A control
  that cannot reach the arm is not a control, which is why this file exists
  rather than four more rows over there.

  NOT BYTE-IDENTICAL TO FPC, DELIBERATELY, AND THE SIBLING FILE IS -- do not
  "fix" this one to match it. Exactly two lines differ and BOTH belong to a
  separate, pre-existing defect that has nothing to do with management
  operators on parameters:

      fpc, and pxx does not print:   `  Init`            (before the first row)
      fpc, and pxx does not print:   `  Fin    id=7`     (in the const section)

  Both are the lifecycle of `Make`'s own RESULT variable, which pxx neither
  Initializes nor Finalizes -- see
  bug-a-a-managed-record-function-result-runs-neither-initialize-nor-finalize.
  Verified against the PINNED compiler on a copy of this program with the AddRef
  operator removed: the pin omits the same two lines, so the gap predates this
  work and is not something the AddRef hook introduced.

  WHEN THAT TICKET LANDS THIS FILE MUST FAIL, and the fix is to add the two
  lines to the .expected -- not to reopen the operator dispatch. Every OTHER
  line here is fpc 3.2.2's, byte for byte. }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    id: Integer;
    pad1, pad2, pad3: Int64;   { > 8 bytes: at or under, pxx refuses outright }
    class operator Initialize(var a: TFoo);
    class operator Finalize(var a: TFoo);
    class operator AddRef(var a: TFoo);
  end;

class operator TFoo.Initialize(var a: TFoo);
begin a.id := 0; WriteLn('  Init'); end;

class operator TFoo.Finalize(var a: TFoo);
begin WriteLn('  Fin    id=', a.id); end;

class operator TFoo.AddRef(var a: TFoo);
begin WriteLn('  AddRef sees id=', a.id); a.id := a.id + 100; end;

{ The non-lvalue. A function result is the ordinary way to write one for a
  record; there is no cast or literal spelling that produces a record rvalue. }
function Make: TFoo;
begin Make.id := 7; end;

procedure TakeVal(f: TFoo);
begin WriteLn('  callee(byval) id=', f.id); end;

procedure TakeConst(const f: TFoo);
begin WriteLn('  callee(const) id=', f.id); end;

procedure Run;
begin
  { AddRef FIRES: a by-value parameter is a copy whatever the argument's shape. }
  WriteLn('-- by value, NON-LVALUE arg --');
  TakeVal(Make);

  { AddRef MUST NOT FIRE: the temp exists for the address, not as a copy. This
    is the row the first emitter got wrong, and the callee's id is what says
    so -- 7 is right, 107 is the operator having run. }
  WriteLn('-- const, NON-LVALUE arg --');
  TakeConst(Make);
end;

begin
  Run;
  WriteLn('-- done --');
end.

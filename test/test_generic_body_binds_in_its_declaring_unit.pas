{ A generic template's method body belongs to the unit that DECLARED it, not to
  whoever specializes it.

  The body is buffered as tokens and streamed to each specialization, then
  re-parsed there — so it used to resolve its names in the SPECIALIZING scope:
  it saw the declaring unit's INTERFACE (via this program's `uses`) and this
  program's own declarations, which SHADOW, and never the declaring unit's
  implementation section. Two observable defects, and row 2 is the dangerous one:

    - `l.FillPriv` ran THIS PROGRAM's PrivFill. A silent wrong answer: the
      method's meaning depended on who specialized it.
    - with no PrivFill here at all, the UNIT stopped compiling —
      `undefined variable (PrivFill)` against a procedure declared ten lines
      above the template method IN THE SAME FILE.

  Row 1 is what makes row 2 readable rather than ambiguous: this program's own
  PrivFill must still be reachable from this program. A fix that simply hid it
  would pass row 2 and break row 1.

  Rows 4 and 5 are the controls that were ALREADY GREEN before the fix, and they
  are here because they are what a wrong fix breaks: an ordinary method in the
  identical shape, and a specialization written inside the declaring unit.
  bug-p-a-generic-template-body-resolves-its-symbols-at-the-specialization-site }
program test_generic_body_binds_in_its_declaring_unit;
{$mode objfpc}
uses ugdecl;

procedure PrivFill;   { deliberately shadows the unit's implementation-private one }
begin WriteLn('program priv'); end;

type TIntList = specialize TList<Integer>;

var l: TIntList; p: TPlain;
begin
  PrivFill;        { 1. this program's own call still reaches its own routine }
  l := TIntList.Create;
  l.FillPriv;      { 2. the template body must reach the UNIT's private helper }
  l.FillIface;     { 3. and its exported one }
  p := TPlain.Create;
  p.FillPriv;      { 4. control: ordinary method, was always correct }
  RunInUnit;       { 5. control: specialized inside its own unit, was correct }
end.

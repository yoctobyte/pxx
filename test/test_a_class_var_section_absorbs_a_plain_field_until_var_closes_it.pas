{ A `const` OR `class var` IN A CLASS BODY OPENS A SECTION, AND A PLAIN FIELD
  DECLARATION AFTER ONE IS ABSORBED INTO IT RATHER THAN ENDING IT. `var` is
  what closes the section and goes back to per-instance storage.

    TC = class
      class var LIMIT: Integer;
      Slot: Integer;        { <- a CLASS var too. One Slot for the whole class. }
    end;

  THIS IS THE LANGUAGE RULE, NOT A DEFECT, AND THE TEST EXISTS TO STOP IT BEING
  RE-FILED AS ONE. It was filed as one:
  bug-a-a-class-var-declared-before-an-instance-field-corrupts-the-instance-layout
  read the symptom as the instance LAYOUT being corrupted -- fields displaced by
  the class var's width, two objects overlapping. Measured 2026-09-19: nothing
  is displaced and no offset is wrong. `PXXDBG=a.reclayout` prints the class
  with NO instance fields at all (`with-fields` one lower, `fields` one lower),
  because the field never became an instance field. Every object reads one
  shared global, which is why constructing a second object appears to empty the
  first -- and why the damage looks like aliasing.

  fpc 3.2.2 ON THIS BOX AGREES, WHICH IS WHY THIS IS PINNED AS PARITY RATHER
  THAN FIXED. The absorbing form prints the same wrong-looking answer under fpc
  from the same source, silently; the const-section form is refused by fpc with
  the same message pxx gives ("=" expected but ";" found). This file is
  {$mode objfpc} and compiles under both, so the parity claim can be re-checked
  with `fpc` and a diff rather than believed.

  THE ROWS ARE CHOSEN SO THE RIGHT ANSWER DIFFERS FROM THE WRONG ONE. Each
  class is constructed TWICE, with 64 first and 1 second. A shared slot answers
  1 (the second construction overwrote the first); a per-instance slot answers
  64. A row that merely compiled would prove nothing here, and both shapes
  compile.

    absorbed        no `var`  -> 1, and reachable as a class var with no instance
    per-instance    `var`     -> 64
    const-then-var  a const section closed by `var` the same way -> 64, TAG 5

  THE `absorbed-class` ROW IS NOT REDUNDANT WITH THE `absorbed` ROW AND MUST NOT
  BE TIDIED AWAY. It names the storage through the CLASS with no instance in
  hand, which only compiles while the field is a class var -- so if the section
  rule is ever "fixed" into per-instance storage this file fails to BUILD rather
  than printing a different number. Verified by control 2026-09-19: adding `var`
  to TAbsorbed gives `error: class method not found (Slot)` at that line. A
  value row alone would have gone red too, but a compile-time assertion cannot
  be satisfied by a coincidence.

  lib/rtl/pil.pas declared its instance fields FIRST for a year to dodge this,
  and said in a comment that it was working around a compiler bug. It is not;
  it needed the `var`. }
{$mode objfpc}
program test_a_class_var_section_absorbs_a_plain_field_until_var_closes_it;
type
  { No `var`: Slot joins the class var section above it. }
  TAbsorbed = class
  public
    class var LIMIT: Integer;
    Slot: Integer;
    constructor Create(v: Integer);
  end;

  { `var` closes the section; Slot is per-instance. }
  TPerInstance = class
  public
    class var LIMIT: Integer;
    var
      Slot: Integer;
    constructor Create(v: Integer);
  end;

  { The same rule one section over: a class const section is closed by `var`
    too. Without it, `Slot: Integer;` is read as another const and refused --
    loud, unlike the class var half, which is the only reason that one is a
    footnote and this one cost a day. }
  TConstThenVar = class
  public
    const TAG = 5;
    var
      Slot: Integer;
    constructor Create(v: Integer);
  end;

constructor TAbsorbed.Create(v: Integer);     begin Slot := v; end;
constructor TPerInstance.Create(v: Integer);  begin Slot := v; end;
constructor TConstThenVar.Create(v: Integer); begin Slot := v; end;

var
  a1, a2: TAbsorbed;
  p1, p2: TPerInstance;
  c1, c2: TConstThenVar;
begin
  a1 := TAbsorbed.Create(64);     a2 := TAbsorbed.Create(1);
  p1 := TPerInstance.Create(64);  p2 := TPerInstance.Create(1);
  c1 := TConstThenVar.Create(64); c2 := TConstThenVar.Create(1);

  WriteLn('absorbed       = ', a1.Slot);
  { The same storage named with no instance at all -- this is what says it
    landed in the class var registry rather than at a wrong instance offset. }
  WriteLn('absorbed-class = ', TAbsorbed.Slot);
  WriteLn('per-instance   = ', p1.Slot);
  WriteLn('const-then-var = ', c1.Slot, ' TAG=', TConstThenVar.TAG);
  if (a2 = nil) or (p2 = nil) or (c2 = nil) then WriteLn('unreachable');
end.

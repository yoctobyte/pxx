program test_qualified_units;

uses qualified_a, qualified_b;

{ Unit-qualified constant in a const expression (bug-unit-qualified-constant-
  not-resolved): `Unit.Const` must resolve in ConstEval, not just in ordinary
  expressions. }
const QC = qualified_a.SharedConst;

{ A program variable spelled exactly like a unit's untyped string const. Both
  readings have to hold: the BARE name is the program's variable (Pascal scoping,
  and the reason the guard being tested exists at all), the QUALIFIED name is the
  unit's const. Verified against FPC 3.2.2, which prints these two lines.
  bug-n-assigning-to-a-name-that-collides-with-a-pascal-shim-attribute-fails }
var SharedTag: AnsiString;

{ THE SHADOW HAS TO BE A CONSTANT, NOT A VARIABLE. The variable case above was
  already guarded and already worked; the constant case is a DIFFERENT name
  table and was never wired to the qualifier, which is why grepping for the
  construct would not have found it -- only grepping for the other spelling's
  handler. Three const kinds, because the failure differed by kind:

    Hidden       untyped string, length >= 2 -> the call silently returned the
                 CONSTANT'S TEXT with the arguments discarded, no diagnostic.
    HiddenSet    set constant -> the baked mask's ADDRESS printed as a string,
                 i.e. a memory dump.
    HiddenEmpty  the empty string -> printed as nothing at all, which is
                 indistinguishable from a blank and so cannot be spotted by eye.

  A char const ('S'), a typed const, an integer and a float const all resolved
  correctly before the fix and are not re-tested here; the boundary is in the
  ticket. Both directions are asserted below: the QUALIFIED name must reach the
  unit's routine, and the BARE name must still reach the program's constant --
  a guard that only checked the first would pass by breaking ordinary Pascal
  scoping. bug-p-a-unit-qualified-reference-is-captured-by-a-same-named-string-const }
const
  Hidden = 'do not use';
  HiddenSet = ['a'..'c'];
  HiddenEmpty = '';

var HiddenN: Integer;

begin
  SharedTag := 'from-program';
  writeln(SharedTag);
  writeln(qualified_a.SharedTag);
  writeln(QC);                          { 1074030207 — const-expression context }
  writeln(qualified_a.SharedConst);     { 1074030207 — ordinary-expression context }
  qualified_a.SetShared(3);
  qualified_b.SetShared(7);
  writeln(qualified_a.SharedValue);
  writeln(qualified_b.SharedValue);
  writeln(qualified_a.SharedFunc);
  writeln(qualified_b.SharedFunc);
  writeln(qualified_a.SharedAdd(1));
  writeln(qualified_b.SharedAdd(1));

  { Qualified, in ARGUMENT position -- the face that failed as a syntax error
    (`expected ')' before '('`) rather than a wrong value. }
  writeln(qualified_a.Hidden(1));        { 501 }
  writeln(qualified_a.HiddenSet(2));     { 602 }
  writeln(qualified_a.HiddenEmpty(3));   { 703 }

  { Qualified, on the right of an ASSIGNMENT -- the face that failed SILENTLY. }
  HiddenN := qualified_a.Hidden(4);
  writeln(HiddenN);                      { 504 }

  { ...and the bare names still reach the program's constants. }
  writeln(Hidden);                       { do not use }
  writeln('c' in HiddenSet);             { TRUE }
  writeln('z' in HiddenSet);             { FALSE }
  writeln('[', HiddenEmpty, ']');        { [] }
end.

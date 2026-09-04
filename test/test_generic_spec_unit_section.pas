{ WHICH SECTION of a unit a generic specialization is minted in, and what that
  means for an importer.

  DesugarImportedDelphiGenericUses mints `TBox$Integer = specialize
  TBox<Integer>;` at the END OF ParseUsesClause -- DGenDeclAnchor returns the
  clause itself for that caller, by design. So the alias row is registered in
  whatever section that clause sits in, and the three rows below are the three
  cases that distinguishes:

    ugsectb  INTERFACE uses      -> the alias is part of what the unit publishes,
                                    and `TIntBox` names it there. An importer
                                    must be able to hold one.
    ugsectc  IMPLEMENTATION uses -> the specialization is that unit's own
                                    business. Its interface publishes an Integer
                                    and nothing else.
    here     the program         -> specializes the SAME template itself. The
                                    minted name is the SAME STRING as ugsectc's,
                                    from the same template, in a different scope.

  The third row is the one with teeth. `TBox$Integer` is a global-looking name
  minted independently by two files, and it stayed correct here only because
  ParseSpecialization decides "this is an exact re-statement, skip it" from a
  VISIBILITY-AWARE FindSpecialization plus the Templates[] index --
  bug-p-a-generic-declaration-does-not-shadow-an-imported-one-of-the-same-name
  is what happens when either half of that answers on a name alone.

  Written when Track D was closing
  bug-p-a-units-implementation-section-is-visible-to-its-importers, which stamps
  every declaration row with the section it was declared in. This slice is the
  one that mints alias rows FROM a uses clause, so these three rows are exactly
  where that boundary meets generics. Baseline measured before that change
  landed: `101 1 202 42 4 yes`, identical to fpc 3.2.2.

  THE LAST TWO COLUMNS. `SizeOf(TBox<ShortInt>) < SizeOf(TBox<Int64>)` is asserted
  as a RELATION, not as two numbers: the widths are alignment-dependent and would
  be a different correct pair per target, while the relation holds everywhere and
  still fails if the two specializations collapse into one. The bare `4` before
  it is SizeOf(b.V) for the Integer arm -- kept because it is the one column that
  says WHICH argument won, and it is deliberately read off a field rather than
  the record.

  WHAT THIS TEST IS AND IS NOT. It is a CHARACTERISATION test, not a regression
  test: the pinned binary passes it unchanged, and no fix of mine is being
  asserted. It exists because a boundary it depends on is about to move under
  someone else's change, and a probe in a scratchpad would not be there when it
  did.

  Both rows were controlled rather than assumed:

  - Row 1 IS sensitive to the section. Moving ugsectb's `uses ugsecta` from its
    interface to its implementation makes this fail outright (`unknown type:
    TBox` at the `TIntBox` declaration) -- so the first column really is
    measuring an interface-section mint and not just "the unit compiles".
  - Row 2 IS WEAKER and should not be read as more than it is. It says an
    implementation-only mint does not break the importer's own mint of the same
    template under the same alias name. It does NOT establish that the two are
    distinct types -- they are structurally identical, so no value assertion
    could tell them apart, and none here pretends to.

  Oracle: FPC 3.2.2 prints the same line. }
program test_generic_spec_unit_section;
{$MODE DELPHI}

uses ugsecta, ugsectb, ugsectc;

var
  fromB: TIntBox;
  mine: TBox<Integer>;
  small: TBox<ShortInt>;
  big: TBox<Int64>;
  rel: string;
begin
  fromB := MakeB;
  mine.V := 42;
  mine.Tag := 3;
  small.V := 1; small.Tag := 4;
  big.V := 2;   big.Tag := 5;
  if SizeOf(small) < SizeOf(big) then rel := 'yes' else rel := 'NO';
  writeln(fromB.V, ' ', fromB.Tag, ' ', MakeC, ' ', mine.V, ' ',
          SizeOf(mine.V), ' ', rel);
end.

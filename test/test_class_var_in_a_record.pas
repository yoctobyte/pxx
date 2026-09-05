{ `class var` in a RECORD -- one shared slot per TYPE, not per instance.

  pxx refused this outright until 2026-09-05, with a comment saying there was
  "no shared-storage model for record class vars". There was: the ClassVar
  registry is keyed by a type index a record already has, and the slot is an
  ordinary anonymous global. What was missing was a caller, and the comment
  described that absence as a limitation of the mechanism.

  THE SHARING IS THE ASSERTION, NOT THE COMPILE. A per-instance field would
  compile every line here and print different numbers, so writing through `a`
  and reading through `b` is the only row that can tell a class var from a
  field. Expected output is fpc 3.2.2's own.

  `class var` IS A SECTION HEADER, NOT A PER-DECLARATION MODIFIER, and this file
  asserts that in both directions because it is the trap. `Tag` below is
  declared BEFORE the section and is per-instance; `AlsoShared` is declared after
  a `class var` and is SHARED even though the words `class var` do not appear on
  its line. Measured against fpc 3.2.2, which agrees. The first draft of this
  test put its per-instance control AFTER the section and asserted `2 2` with a
  comment claiming it proved fields stay per-instance -- a true expected value
  with a false explanation, and a control that could not have failed.

  What is NOT covered, deliberately: a class PROPERTY backed by a class var
  (`class property V: T read FV write FV`). The accessor resolver and the lvalue
  path both only know field- and method-backed properties, so that spelling is
  still refused -- bug-p-a-class-property-cannot-be-backed-by-a-class-var. Five
  conformance rows need both halves; this is the first.

  Two contexts stay REFUSED and are asserted in the Makefile, since a refusal
  cannot sit in a program that must compile: a record in a local type section,
  and an anonymous record. Both are FPC's rule, and both are `%FAIL` conformance
  rows that pass BY REFUSAL -- lifting the rejection wholesale would have fixed
  five rows and broken two. }
program test_class_var_in_a_record;
{$mode delphi}

type
  TCounter = record
    Tag: LongInt;                 { before the section: per-instance }
    class var
      Count: LongInt;
      AlsoShared: LongInt;        { still in the section -- shared }
    class procedure Bump; static;
  end;

  TOther = record
    class var Count: LongInt;     { same member name, different record }
  end;

class procedure TCounter.Bump;
begin
  Inc(Count);
end;

var
  a, b: TCounter;
begin
  TCounter.Count := 0;
  TOther.Count := 100;

  { qualified by the TYPE }
  TCounter.Bump;
  TCounter.Bump;
  WriteLn(TCounter.Count);

  { qualified by an INSTANCE -- same slot }
  a.Count := 41;
  WriteLn(b.Count);

  { a field declared BEFORE the section is still per-instance }
  a.Tag := 1;
  b.Tag := 2;
  WriteLn(a.Tag, ' ', b.Tag);

  { a declaration AFTER `class var` is in the section and is shared }
  a.AlsoShared := 7;
  WriteLn(b.AlsoShared);

  { two records with the same class var name do not share }
  WriteLn(TOther.Count);

  { and a static method sees it as its own scope }
  TCounter.Count := 5;
  TCounter.Bump;
  WriteLn(TCounter.Count);
end.

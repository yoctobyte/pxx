program test_two_aliases_of_one_specialization_are_one_class;
{$mode objfpc}
{ `TIntBox = specialize TBox<Integer>` and `TIntBox2 = specialize TBox<Integer>`
  are ONE type in Pascal. Each alias minted its own class, so they were two:
  `a1 is TIntBox2` answered FALSE where fpc 3.2.2 answers TRUE.
  bug-p-a-nested-specialization-is-named-by-its-alias-so-one-name-serves-every-outer-specialization

  THE ASSIGNMENT IS WHAT HID IT, so it is row 1 rather than the assertion.
  `a2 := a1` was accepted by BOTH compilers while only the identity test
  disagreed, so any fixture built around passing values around prints the same
  thing on a broken compiler as on a correct one.

    1  assign     a2 := a1 across the two names, then read the field  (the decoy)
    2  is-same    a1 is TIntBox2                        TRUE   <- the bug
    3  as-same    (a1 as TIntBox2).f                    7
    4  is-other   TObject(a1) is TStrBox                FALSE  <- the control
    5  method     one method, reached through both names        (not duplicated)
    6  distinct   a StrBox really is its own class      TRUE
    7  onename    a1.ClassName = a2.ClassName           TRUE   <- a RELATION

  ROW 4 IS THE POSITIVE CONTROL AND IT IS DRAWN FROM THE POPULATION THE FIX
  CHANGES: collapsing two aliases into one class is only correct while the
  arguments AGREE, and a collapse that ignored the arguments would answer TRUE
  here. Rows 2 and 4 must disagree with each other or nothing was tested.

  It goes through TObject deliberately. Spelled `a1 is TStrBox` directly, fpc
  3.2.2 refuses the program at COMPILE time -- "Class or Object types
  TBox<System.LongInt> and TBox<System.ShortString> are not related" -- so the
  row that has to print FALSE cannot be written that way and still have an
  oracle. Widening the static type to TObject is what makes the question
  runtime, which is where the answer lives.

  ROW 7 ASSERTS THE RELATION AND NOT THE NAME, deliberately. One type has one
  ClassName, which is the property under test and is true of both compilers;
  the SPELLING is not shared and asserting it would bake in a divergence that
  is not this ticket's. Measured 2026-09-08: fpc prints
  `TBox<System.LongInt>` for both, pin v407 printed `TIntBox` and `TIntBox2`
  (two names, the defect), and pxx now prints `TIntBox` for both -- fpc's
  shape, not fpc's spelling. }

type
  generic TBox<T> = class
    f: T;
    function Twice: T;
  end;

  TIntBox  = specialize TBox<Integer>;
  TIntBox2 = specialize TBox<Integer>;    { the SAME type, spelled twice }
  TStrBox  = specialize TBox<String>;     { a different one }

function TBox.Twice: T;
begin
  Result := f + f;
end;

var
  a1: TIntBox;
  a2: TIntBox2;
  s1: TStrBox;
  o: TObject;
begin
  a1 := TIntBox.Create;
  a1.f := 7;
  a2 := a1;
  Writeln('assign ', a2.f);                          { 7 }
  Writeln('is-same ', a1 is TIntBox2);               { TRUE }
  Writeln('as-same ', (a1 as TIntBox2).f);           { 7 }
  o := a1;
  Writeln('is-other ', o is TStrBox);                { FALSE }
  Writeln('method ', a1.Twice, ' ', a2.Twice);       { 14 14 }
  s1 := TStrBox.Create;
  s1.f := 'ab';
  Writeln('distinct ', s1 is TStrBox, ' ', s1.Twice);  { TRUE abab }
  Writeln('onename ', a1.ClassName = a2.ClassName);    { TRUE }
end.

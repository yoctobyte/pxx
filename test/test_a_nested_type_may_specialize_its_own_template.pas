program test_a_nested_type_may_specialize_its_own_template;
{ A GENERIC CLASS COULD NOT NAME ITSELF IN ITS OWN NESTED TYPE SECTION:

    generic TTest<T> = class
    type
      TTestT = specialize TTest<T>;      { names its OWN template }
    end;
    TI = specialize TTest<LongInt>;      -> expected '<' before ';'

  This is what fpc's own tgeneric99 opens with, and it is how a generic
  container names its own iterator or node type.

  THE BOUNDARY IS THE `=`, NOT THE SELF-REFERENCE, and rows 3 and 4 are here to
  say so rather than to pass. After `=` a `specialize` group is a DECLARATION
  and must mint a class, so the group recogniser deliberately refused it and
  left it to the deferral machinery -- right for every template but the one
  being streamed, for which minting is the one thing that cannot be done, since
  that class does not exist yet. It fell through to the verbatim copy, where the
  identifier arm renames the template's own name to the specialization's:
  `specialize TI<LongInt>`, i.e. `generic template TI not found`. With the
  parameter still in it the truncated parse says `expected '<' before ';'`
  instead. TWO MESSAGES, ONE EXCLUSION -- and row 4 is the one that produced the
  second, which is why both spellings are here and not just the tidier one.

  ROW 3 IS THE CONTROL THAT LOCATES THE DEFECT. The identical self-reference in
  a USE position (`Nxt: specialize TTest<T>`) compiled and ran correctly
  throughout -- on pin v407 too. A fixture with only the declaration rows would
  pass while saying nothing about which half was broken.

  ROW 5 IS THE OTHER-TEMPLATE CONTROL: a nested type specializing a DIFFERENT
  template still has to MINT, and that path must not be disturbed by this. It
  worked before and must keep working, so a regression here reads as this change
  having widened rather than aimed. It is built from INSIDE the template on
  purpose -- reaching a minted nested type through the OUTER specialization's
  name (`TI.TMinted.Create`) is a separate gap, still open, and routing this row
  through it would make the control fail for a reason that is not its own.

  DELIBERATELY ABSENT: `TOtherArg = specialize TTest<Double>` inside
  `TTest<LongInt>` -- the same template at DIFFERENT arguments. It still fails,
  and that is not a residual: fpc 3.2.2 refuses that program too (`Syntax error,
  "identifier" expected but ";" found`), so a nested type may name its own
  template only at its own arguments. Asserting our diagnostic for it would
  freeze a message on code the language does not accept.

  Oracle: fpc 3.2.2 prints all five rows exactly as below.
  bug-p-a-nested-type-that-specializes-its-own-template-is-renamed-to-the-outer-specialization }
{$mode objfpc}{$H+}
type
  generic TOther<T> = class
    W: T;
  end;

  generic TTest<T> = class
  type
    TSelfParam = specialize TTest<T>;         { row 4: self, via the PARAMETER }
    TSelfLong  = specialize TTest<LongInt>;   { row 2: self, at its OWN argument }
    TMinted    = specialize TOther<T>;        { row 5: a DIFFERENT template }
  var
    V: T;
    Nxt: specialize TTest<T>;                 { row 3: self, in a USE position }
    Other: TMinted;
    { built from INSIDE the template, which is where a nested minted type is
      actually used -- and it sidesteps reaching TMinted through the outer
      specialization's name, which is a different gap and not this one. }
    procedure MakeOther(w: T);
  end;

  TI = specialize TTest<LongInt>;

procedure TTest.MakeOther(w: T);
begin
  Other := TMinted.Create;
  Other.W := w;
end;

var
  a, b: TI;
  viaParam: TI.TSelfParam;
  viaLong: TI.TSelfLong;
begin
  a := TI.Create; a.V := 7;
  b := TI.Create; b.V := 9;
  a.Nxt := b;
  WriteLn('own value  = ', a.V);
  WriteLn('use posn   = ', a.Nxt.V);

  viaParam := TI.TSelfParam.Create; viaParam.V := 11;
  WriteLn('decl param = ', viaParam.V);
  viaLong := TI.TSelfLong.Create; viaLong.V := 13;
  WriteLn('decl concr = ', viaLong.V);

  a.MakeOther(17);
  WriteLn('other tmpl = ', a.Other.W);
end.

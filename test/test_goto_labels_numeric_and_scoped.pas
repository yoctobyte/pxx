{ goto labels: NUMERIC labels, and label scoping across routines.

  Two defects, found together on 2026-08-22 by an fpc differential sweep:

  1. `label 1;` was refused outright ("Expected: begin"). Only IDENTIFIER
     labels parsed -- the label section, the `n:` statement position and
     `goto n` all took tkIdent only. Numeric labels are the traditional
     Pascal spelling and appear in every ported listing.

  2. A routine's own label section CLOBBERED the enclosing program's labels.
     Entering a body reset GotoLabelCount to 0 and restored it on exit, which
     restored the COUNT but not the slot CONTENTS -- so the routine's labels
     were written over the program's, and the main body's own `la:` then died
     with "AN_LABEL: undeclared label". Independent of (1): the same program
     with identifier labels failed identically.

  Output is byte-identical to fpc 3.2.2 -Mobjfpc -O1's on this source. }
program test_goto_labels_numeric_and_scoped;

label 1, 2, la, done;

var
  i, trips: Integer;

{ (2): a routine with its own numeric label, declared BEFORE the main body,
  which is what overwrote the program's slots }
procedure NumericInRoutine;
label 1;
var k: Integer;
begin
  k := 0;
1:
  Inc(k);
  if k < 3 then goto 1;
  WriteLn('routine.numeric k=', k);
end;

{ a sibling reusing the SAME label names, plus a nested routine reusing them
  again -- three scopes, one set of names }
procedure Shadowing;
label m;
  procedure Nested;
  label m;
  begin
    goto m;
    WriteLn('nested.skipped');
  m:
    WriteLn('nested.m');
  end;
begin
  Nested;
  goto m;
  WriteLn('shadow.skipped');
m:
  WriteLn('shadow.m');
end;

{ identifier labels in a routine, the (2) case in its original form }
procedure IdentInRoutine;
label lp;
var k: Integer;
begin
  k := 0;
lp:
  Inc(k);
  if k < 2 then goto lp;
  WriteLn('routine.ident k=', k);
end;

begin
  { a numeric label as a backward branch target }
  i := 0;
1:
  Inc(i);
  if i < 4 then goto 1;
  WriteLn('main.numeric i=', i);

  { a numeric label as a FORWARD branch target -- the goto is fixed up later }
  goto 2;
  WriteLn('main.skipped-forward');
2:
  WriteLn('main.forward');

  { the routines whose own labels used to overwrite these }
  NumericInRoutine;
  IdentInRoutine;
  Shadowing;

  { the program's identifier labels must still resolve AFTER those routines }
  trips := 0;
la:
  Inc(trips);
  if trips < 2 then goto la;
  WriteLn('main.ident trips=', trips);

  goto done;
  WriteLn('main.skipped-done');
done:
  WriteLn('main.done');
end.

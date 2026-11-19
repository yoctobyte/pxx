program test_a_class_named_after_a_unit_the_importer_does_not_use;
{ This program uses ucncollide only. The unit ucnwidget is NOT in its uses, so
  that name is not in scope here (fpc's rule for unit names), and
  `Ucnwidget.Create` is the class ucncollide exports. pxx took the name as a
  unit qualifier and failed with "undefined variable (Create)".
  bug-a-a-class-named-after-a-used-unit-cannot-be-constructed-from-outside-that-unit }
{$MODE PXX}
uses ucncollide;
var a, b: Ucnwidget;
begin
  a := Ucnwidget.Create(7);
  b := MakeHere(4);
  WriteLn(a.n, ' ', b.n, ' ', a is Ucnwidget);
end.

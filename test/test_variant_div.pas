program test_variant_div;
{ Variant div / mod / real-division: div,mod integer-only; / always Double. }
var a, b, r: Variant;
begin
  a := 17; b := 5;
  r := a div b;  writeln(r);   { 3 }
  r := a mod b;  writeln(r);   { 2 }
  r := a / b;    writeln(r);   { 3.4 }
  a := 10; b := 4;
  r := a / b;    writeln(r);   { 2.5 }
end.

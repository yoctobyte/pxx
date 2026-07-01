program test_narrowing_typecast_rvalue;
var i: integer;
begin
  i := 300;
  writeln(byte(i));                        { 44 }
  if byte(i) = 44 then writeln('cmp-ok') else writeln('cmp-fail');
  writeln(byte(i) and $FF);                 { 44, unrelated pre-existing path }
  writeln(byte(i) mod 256);                 { 44, unrelated pre-existing path }

  i := 70000;
  writeln(word(i));                         { 4464 }

  i := -1;
  writeln(cardinal(i));                     { 4294967295 }
  writeln(longword(i));                     { 4294967295 }
  writeln(integer(i));                      { -1, unchanged passthrough }

  i := 200;
  writeln(shortint(i));                     { -56 }

  i := 5;
  writeln(byte(i));                         { 5, no-op case still correct }
  writeln(shortint(i));                     { 5, no-op case still correct }
end.

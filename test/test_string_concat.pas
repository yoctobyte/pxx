program TestStringConcat;
var
  s, t, z: string;
begin
  s := 'Hello';
  t := 'World';
  z := s + ', ' + t + '!';
  writeln(z);
  
  z := s + ' there!';
  writeln(z);

  z := 'Hi ' + t;
  writeln(z);
end.

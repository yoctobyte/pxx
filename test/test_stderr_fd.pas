{ writeln(StdErr, ...) must go to fd 2, plain writeln to fd 1. Mixed value
  kinds (string/integer/width/boolean) on the StdErr line must all land on fd 2.
  bug-stderr-not-fd2. }
program test_stderr_fd;
var i: Integer;
begin
  writeln('out1');
  write(StdErr, 'e1 ');
  i := 7;
  writeln(StdErr, 'n=', 42, ' i=', i:3, ' b=', True);
  writeln('out2');
end.

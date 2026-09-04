program TestDeepRaise;
{ A RAISE FROM DEEP ENOUGH THAT THE REGISTER FILE HAS WRAPPED, and a try frame
  whose own registers must survive the landing.

  test_cross_exception raises one frame below the try, which on xtensa windowed
  is shallow enough that the register file may never overflow -- so it passes
  whether or not the unwind spills. 40 frames is past a wrap of a 64-register
  file however the core is configured, so every intermediate frame is in memory
  when the longjmp runs and the try frame has to be reloaded from there.

  The four locals are the second half of the assertion. A windowed longjmp
  restores the try frame from TWO save areas in two different places (a0-a3 at
  the callee's [sp-16], a4-a7 at the frame's own [caller_sp-32]) and getting
  only the first right still lands, still prints `caught`, and comes back with
  half the frame wrong. Printing them individually rather than only their sum
  means a compensating pair cannot hide.
  bug-a-xtensa-windowed-refuses-ir-raise-because-unwind-needs-the-windows-spilled }
var
  total: Integer;

procedure Deep(n: Integer);
begin
  if n = 0 then
    raise 4242;
  Deep(n - 1);
  total := total + n;
end;

procedure Run;
var
  a, b, c, d: Integer;
begin
  a := 11;
  b := 22;
  c := 33;
  d := 44;
  try
    Deep(40);
    writeln(999);
  except
    writeln('caught');
  end;
  writeln(a);
  writeln(b);
  writeln(c);
  writeln(d);
end;

{ A TRY IN THE MAIN PROGRAM BODY, which is a different frame from every other
  one in the program and was the shape that crashed.

  The process entry runs in the ROOT window and reaches its frame through a
  bare `entry`, never through a CALL8, so nothing ever writes the 16-byte block
  below its stack pointer that every other frame gets from its caller. The
  windowed unwind walks that chain, so this `try` dereferenced garbage and
  SIGSEGV'd while `Run`'s identical `try` one procedure down worked. Everything
  above this line passed the whole time. }
begin
  total := 0;
  Run;
  writeln(total);
  try
    Deep(40);
    writeln(999);
  except
    writeln('caught at top level');
  end;
  writeln(total);
end.

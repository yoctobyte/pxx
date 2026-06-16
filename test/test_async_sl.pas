program TestAsyncSL;
{ Stackless async coroutines: `; async; stackless;` + `await` + AsyncGo +
  SLRunUntilDone. Two coroutines interleave at their `await` points with NO heap
  stack and NO context switch — a pure compiler state-machine transform (reusing
  the stackless-generator machinery), so it runs on every target with zero asm. }
uses slgen, slsched;

procedure A; async; stackless;
var i: Integer;
begin
  i := 0;
  while i < 3 do
  begin
    writeln('A', i);
    i := i + 1;
    await;
  end;
end;

procedure B; async; stackless;
var j: Integer;
begin
  j := 0;
  while j < 2 do
  begin
    writeln('B', j);
    j := j + 1;
    await;
  end;
end;

begin
  AsyncGo(@A);
  AsyncGo(@B);
  SLRunUntilDone;
  writeln('done');
end.

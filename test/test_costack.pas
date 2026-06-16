program TestCoStack;
{ Configurable per-coroutine heap-stack size (SpawnSized) + the low-end canary.
  Spawns several coroutines on small 8 KB stacks; each does a little recursion
  and yields. They interleave and finish without tripping the overflow guard,
  proving small stacks work and the canary survives ordinary use. }
uses scheduler;

function Sum(n: Integer): Integer;
begin
  if n <= 0 then Sum := 0
  else Sum := n + Sum(n - 1);
end;

procedure Worker(arg: Pointer);
var i, n: Integer;
begin
  n := Integer(arg);
  for i := 1 to 2 do
  begin
    writeln('w', n, ':', Sum(n * 10));
    CoYield;
  end;
end;

begin
  SpawnSized(@Worker, Pointer(1), 8192);
  SpawnSized(@Worker, Pointer(2), 8192);
  SpawnSized(@Worker, Pointer(3), 8192);
  RunUntilDone;
  writeln('all done');
end.

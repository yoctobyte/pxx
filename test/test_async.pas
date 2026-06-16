program TestAsync;
{ Async language surface: the `; async;` routine directive + the `await` marker.
  v1 is the STACKFUL backend — `await` is documentary: `await E` evaluates as `E`,
  and the awaited routine suspends on its own (here a plain CoYield / CoSleep on
  the cooperative scheduler). Proves the surface parses and lowers identically to
  the bare-call form; runs on the shipped stackful engine. }
uses scheduler;

{ A suspending helper: yields the thread a few times (cooperative). }
function Step(label_, n: Integer): Integer; async;
var i: Integer;
begin
  for i := 1 to n do
  begin
    writeln('a', label_, ':', i);
    CoYield;
  end;
  Step := label_ * 100 + n;
end;

procedure Worker(arg: Pointer); async;
var r: Integer;
begin
  r := await Step(Integer(arg), 2);   { expression-position await }
  writeln('done', Integer(arg), '=', r);
end;

begin
  Spawn(@Worker, Pointer(1));
  Spawn(@Worker, Pointer(2));
  RunUntilDone;
  writeln('all done');
end.

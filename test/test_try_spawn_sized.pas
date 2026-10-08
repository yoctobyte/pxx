program test_try_spawn_sized;
{ scheduler.TrySpawnSized and CoStackHighWater (museum_landkaart: a 12-way
  page-load burst on the C3 exhausted the heap, and SpawnSized's GetMem called
  esp_system_abort -- the board rebooted instead of refusing one connection).
  On the host the refusal is driven by the slot table (MAX_CO): every spawn
  past it answers False rather than Halt(216), and a drained table spawns
  again. The ESP heap arm (a heap_caps_get_largest_free_block precheck)
  is exercised on the device. }
uses scheduler;

var hw: Int64; n, k: Integer; refused: Boolean;

procedure Deep(d: Integer);
var pad: array[0..63] of Int64; i: Integer;
begin
  for i := 0 to 63 do pad[i] := d + i + 1;
  if d > 0 then Deep(d - 1);
  if pad[0] < 0 then writeln('unreachable');
end;

procedure Body(arg: Pointer);
begin
  Deep(20);
  hw := CoStackHighWater;
end;

procedure Idle(arg: Pointer);
begin
  CoYield;
end;

begin
  writeln('outside ', CoStackHighWater);
  writeln('spawn ', TrySpawnSized(@Body, nil, 65536));
  RunUntilDone;
  writeln('high water plausible ', (hw > 20 * 512) and (hw < 65536));
  n := 0;
  refused := False;
  for k := 1 to 1000 do
    if TrySpawnSized(@Idle, nil, 4096) then Inc(n)
    else begin refused := True; Break; end;
  writeln('spawned some ', n > 0, ', then refused ', refused);
  RunUntilDone;
  writeln('after drain ', TrySpawnSized(@Idle, nil, 4096));
  RunUntilDone;
  writeln('done');
end.

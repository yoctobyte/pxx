program ExcProto;

{ Phase 5 prototype oracle. Exercises exactly the compositions the
  pending-flag exception design must survive:
    A  normal path through nested try/finally inside a try/except
    B  an exception crossing two frames, each with a finally
    C  an exception escaping a while loop, finally in the loop body
    D  an inner handler that catches and re-raises to an outer one
    E  break and Exit() leaving a try/finally — the same finally body, and
       the same mechanism, reached from two more non-exceptional paths
  Traces are plain integers so the native run can be diffed byte-for-byte
  against the hand-compiled wasm run. }

var
  i: Integer;

function EarlyExit(n: Integer): Integer;
begin
  Result := -1;
  try
    if n = 1 then
      Exit(42);
    Result := 7;
  finally
    writeln(8000 + n);
  end;
  Result := 99;
end;

function Thrower(n: Integer): Integer;
begin
  Result := 0;
  if n > 2 then
    raise (100 + n);
  Result := n * 10;
end;

function Middle(n: Integer): Integer;
begin
  { no handler here: pure propagation through a frame that owns a finally }
  try
    Result := Thrower(n);
    writeln(1000 + Result);
  finally
    writeln(2000 + n);
  end;
end;

begin
  { A }
  try
    try
      writeln(Middle(1));
    finally
      writeln(3001);
    end;
  except
    writeln(4001);
  end;

  { B }
  try
    try
      writeln(Middle(5));
    finally
      writeln(3002);
    end;
  except
    writeln(4002);
  end;

  { C }
  try
    i := 0;
    while i < 4 do
    begin
      try
        Inc(i);
        writeln(5000 + i);
        if i = 2 then
          raise 777;
      finally
        writeln(6000 + i);
      end;
    end;
  except
    writeln(4003);
  end;

  { D }
  try
    try
      raise 888;
    except
      writeln(7001);
      raise;
    end;
  except
    writeln(7002);
  end;

  { E }
  i := 0;
  while i < 5 do
  begin
    try
      Inc(i);
      if i = 3 then
        break;
    finally
      writeln(8500 + i);
    end;
  end;
  writeln(EarlyExit(1));
  writeln(EarlyExit(0));

  writeln(9999);
end.

program ExcSlice;
{ Exceptions on wasm32 — the compositions, not the syntax.

  wasm cannot jump into another function's frame, so unwinding is not one
  mechanism but two, and every case below is chosen to put a different one
  under load:

    within a frame   the raise branches to the enclosing handler's landing pad
                     through the br_table the body already has
    across frames    the raise sets a pending flag and RETURNS, and the caller
                     checks the flag after the call and asks the same question
                     of its own frame

  Which of the two happens is a runtime comparison — is the innermost handler
  frame MINE? — so a case that never leaves one frame exercises neither the
  comparison nor the propagation, and a case that always leaves exercises only
  half of the pad logic. Hence both, nested, and with `finally` in between.

  `Val` is here for a third reason: a call in VALUE position leaves its result
  on the operand stack, and the flag check branches. The result has to be
  spilled to a local first or the branch carries a half-built expression, which
  is the one thing wasm's validator will not let you get wrong quietly. }

type
  TAlpha = class
    Code: Integer;
  end;
  TBeta = class(TAlpha)
  end;

var
  i, n: Integer;
  a: TAlpha;
  b: TBeta;

procedure Deep;
begin
  writeln('deep-in');
  raise 11;                      { two frames up to the nearest handler }
  writeln('deep-unreachable');
end;

procedure Middle;
begin
  writeln('mid-in');
  try
    Deep;
    writeln('mid-unreachable');
  finally
    writeln('mid-finally');      { runs on the way out }
  end;
  writeln('mid-unreachable-2');
end;

function Val: Integer;
begin
  Val := 5;
  raise 12;                      { a raise from VALUE position }
end;

procedure EarlyExit;
begin
  try
    writeln('exit-body');
    Exit;
  finally
    writeln('exit-finally');     { the continuation is a value, not a path }
  end;
  writeln('exit-unreachable');
end;

begin
  { A: the normal path — nothing raised, both blocks still run in order. }
  try
    try
      writeln('A-body');
    finally
      writeln('A-finally');
    end;
  except
    writeln('A-unreachable');
  end;

  { B: two frames, each owning a finally. }
  try
    Middle;
    writeln('B-unreachable');
  except
    writeln('B-caught');
  end;

  { C: escaping a loop, with a finally inside the loop body. }
  try
    i := 0;
    while i < 3 do
    begin
      Inc(i);
      try
        writeln('C-iter');
        if i = 2 then raise 13;
      finally
        writeln('C-finally');
      end;
    end;
    writeln('C-unreachable');
  except
    writeln('C-caught');
  end;

  { D: catch and re-raise outward. }
  try
    try
      raise 14;
    except
      writeln('D-inner');
      raise;
    end;
  except
    writeln('D-outer');
  end;

  { E: break and Exit through a finally. }
  i := 0;
  while i < 5 do
  begin
    Inc(i);
    try
      if i = 2 then break;
    finally
      writeln('E-finally');
    end;
  end;
  writeln('E-after ', i);
  EarlyExit;

  { F: a raise from a function called in value position. }
  try
    writeln(Val);
    writeln('F-unreachable');
  except
    writeln('F-caught');
  end;

  { G: typed handlers, including a DESCENDANT reaching its ancestor's arm. }
  a := TAlpha.Create;
  a.Code := 41;
  try
    raise a;
  except
    on E: TAlpha do writeln('G-alpha ', E.Code);
    else writeln('G-unreachable');
  end;

  b := TBeta.Create;
  b.Code := 42;
  try
    raise b;
  except
    on E: TBeta do writeln('G-beta ', E.Code);
    else writeln('G-unreachable-2');
  end;

  try
    raise b;
  except
    on E: TAlpha do writeln('G-desc-to-ancestor');
    else writeln('G-unreachable-3');
  end;

  { H: no arm matches, so it leaves the inner handler and reaches the outer. }
  try
    try
      raise 15;
    except
      on E: TAlpha do writeln('H-unreachable');
    end;
  except
    writeln('H-outer');
  end;

  { I: the handler itself is protected by the NEXT try out. }
  n := 0;
  try
    try
      raise 16;
    except
      Inc(n);
      raise 17;
    end;
  except
    writeln('I-outer ', n);
  end;

  writeln('done');
end.

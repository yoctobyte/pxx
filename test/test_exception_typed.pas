program TestExceptionTyped;

type
  TAlphaError = class
    Code: Integer;
  end;
  TBetaError = class
    Code: Integer;
  end;

var
  A: TAlphaError;
  B: TBetaError;

begin
  A := TAlphaError.Create;
  A.Code := 41;
  try
    raise A;
  except
    on E: TAlphaError do writeln(E.Code);
    else writeln(900);
  end;

  B := TBetaError.Create;
  B.Code := 42;
  try
    raise B;
  except
    on E: TAlphaError do writeln(901);
    on E: TBetaError do writeln(E.Code);
    else writeln(902);
  end;

  try
    try
      raise B;
    except
      on E: TAlphaError do writeln(903);
    end;
  except
    writeln(43);
  end;

  try
    raise 44;
  except
    on E: TAlphaError do writeln(904);
    else writeln(44);
  end;

  try
    raise TAlphaError.Create;
  except
    on E: TAlphaError do writeln(45);
    else writeln(905);
  end;
end.

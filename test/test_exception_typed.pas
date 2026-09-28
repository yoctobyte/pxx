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

  { A FRESH object, not B: the handler above freed B, as fpc's does, so raising
    B again raised a dangling pointer. That passed while a handled exception was
    freed without its destructor; once Destroy ran first (846a574b00) it went
    through the freed block's VMT word and segfaulted. fpc survives the same
    program only because its heap leaves the dead VMT in place. }
  try
    try
      raise TBetaError.Create;
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

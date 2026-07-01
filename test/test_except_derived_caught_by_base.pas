program test_except_derived_caught_by_base;
uses sysutils;

type
  EMy = class(Exception) end;
  EMyGrandchild = class(EMy) end;
  EUnrelated = class(Exception) end;

begin
  { base handler catches a direct-derived class }
  try raise EMy.Create('derived');
  except on E: Exception do writeln('caught1:', E.Message); end;

  { base handler catches a two-level-derived (grandchild) class }
  try raise EMyGrandchild.Create('grandchild');
  except on E: Exception do writeln('caught2:', E.Message); end;

  { exact-type handler still works }
  try raise EMy.Create('exact');
  except on E: EMy do writeln('caught3:', E.Message); end;

  { most-specific-first: exact handler listed before the base one still wins }
  try raise EMy.Create('specific');
  except
    on E: EMy do writeln('caught4-specific:', E.Message);
    on E: Exception do writeln('caught4-base:', E.Message);
  end;

  { unrelated sibling class is NOT caught by an EMy-only handler; falls to the
    catch-all Exception handler in the same chain }
  try raise EUnrelated.Create('sibling');
  except
    on E: EMy do writeln('WRONG:', E.Message);
    on E: Exception do writeln('caught5:', E.Message);
  end;

  writeln('done');
end.

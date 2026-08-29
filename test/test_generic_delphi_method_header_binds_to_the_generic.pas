{ A mode-Delphi generic method impl header `TSvc<T>.Sel` must bind to the
  GENERIC TSvc, not to a same-named non-generic class that happens to declare a
  method of the same name.

  DelphiRewriteGenericUses rewrites the header to the objfpc spelling `TSvc.Sel`
  by deleting the `<T>` group, which also deletes the only thing distinguishing
  it from the non-generic class's own impl. The body was then compiled in the
  ordinary class's scope, where the template's class vars do not exist, and
  every reference to one was reported as an undefined variable.

  Both halves are needed to trigger it: the two classes must share a NAME and
  also share a METHOD name. Each half alone already worked, so both are covered
  below to keep the fix from being narrowed to only the failing combination.

  bug-p-a-generic-methods-out-of-line-header-binds-to-a-same-named-non-generic-class }
program test_generic_delphi_method_header_binds_to_the_generic;
{$MODE DELPHI}{$H+}
type
  TSvc = class
  private
    class function Sel: LongInt; virtual;
  public
    class function Run: LongInt;
  end;

  { same name as TSvc, and Sel collides too -- the failing combination }
  TSvc<T> = class(TSvc)
  private class var
    FBump: LongInt;
  private
    class function Sel: LongInt; override;
  public
    class procedure Bump;
  end;

  { same name, but Only collides with nothing -- already worked, kept as a guard }
  TAlt = class
  public
    class function Plain: LongInt;
  end;

  TAlt<T> = class(TAlt)
  private class var
    FN: LongInt;
  public
    class function Only: LongInt;
  end;

class function TSvc.Sel: LongInt;
begin
  Result := 100;
end;

class function TSvc.Run: LongInt;
begin
  Result := Sel;
end;

class function TSvc<T>.Sel: LongInt;
begin
  Result := FBump + SizeOf(T);
end;

class procedure TSvc<T>.Bump;
begin
  FBump := FBump + 1;
end;

class function TAlt.Plain: LongInt;
begin
  Result := 7;
end;

class function TAlt<T>.Only: LongInt;
begin
  FN := FN + 2;
  Result := FN;
end;

type
  TH = TSvc<Int64>;
  TA = TAlt<LongInt>;
begin
  { the non-generic still resolves to its own body }
  WriteLn(TSvc.Run);
  WriteLn(TSvc.Sel);
  { the generic sees its own class var, and the override is dispatched }
  TH.Bump;
  TH.Bump;
  WriteLn(TH.Sel);
  WriteLn(TH.Run);
  { the non-colliding pair is unaffected }
  WriteLn(TAlt.Plain);
  WriteLn(TA.Only);
  WriteLn(TA.Only);
end.

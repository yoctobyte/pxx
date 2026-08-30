program cr;
type
  TBase = class
  public
    function Name: string; virtual;
  end;
  TMid = class(TBase)
  public
    function Name: string; override;
  end;
  TLeaf = class(TMid)
  public
    function Name: string; override;
  end;
  TBaseClass = class of TBase;

function TBase.Name: string; begin Name := 'base'; end;
function TMid.Name: string; begin Name := 'mid'; end;
function TLeaf.Name: string; begin Name := 'leaf'; end;

var b: TBase; m: TMid; l: TLeaf; c: TBaseClass;
begin
  b := TBase.Create; m := TMid.Create; l := TLeaf.Create;

  { `is` down and up the chain }
  WriteLn('b is TBase  ', b is TBase);
  WriteLn('b is TMid   ', b is TMid);
  WriteLn('l is TBase  ', l is TBase);
  WriteLn('l is TMid   ', l is TMid);
  WriteLn('l is TLeaf  ', l is TLeaf);
  WriteLn('m is TLeaf  ', m is TLeaf);

  { through a base-typed reference }
  b := l;
  WriteLn('via base    ', b is TLeaf, ' ', b is TMid, ' ', b.Name);

  { `as` — the checked downcast }
  WriteLn('as TMid     ', (b as TMid).Name);
  WriteLn('as TLeaf    ', (b as TLeaf).Name);

  { a class-of variable: the metaclass as a VALUE }
  c := TLeaf;
  WriteLn('classref eq ', c = TLeaf, ' ', c = TMid);
  c := TMid;
  WriteLn('classref re ', c = TMid, ' ', c = TLeaf);

  WriteLn('done');
end.

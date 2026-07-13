{ VIRTUAL CLASS METHODS dispatch on the RUNTIME class.

  `class function JSONType: TJSONType; virtual;` (fpjson) read through a base-typed reference
  must answer for the object actually there. Ours bound STATICALLY, so TJSONData's base body
  ran and every `Get(name, default)` in fpjson returned the default -- silently.

  A class method's Self is the METACLASS (the RTTI blob), not an instance, so IR_VIRTUAL_CALL
  cannot be reused: it loads the VMT from [Self + 0], which on a blob is the name pointer. The
  blob keeps its VMT at +24, so the call lowers to

      code := [[Self + 24] + slot * PtrSize]

  and an IR_CALL_IND -- ordinary loads, target-independent, no backend op. }
program test_virtual_class_method_b290;
type
  TBase = class
    class function Kind: Integer; virtual;
    class function Name: string; virtual;
  end;
  TMid = class(TBase)
    class function Kind: Integer; override;
    class function Name: string; override;
  end;
  TLeaf = class(TMid)
    class function Kind: Integer; override;
  end;
class function TBase.Kind: Integer; begin Result := 0; end;
class function TBase.Name: string; begin Result := 'base'; end;
class function TMid.Kind: Integer;  begin Result := 1; end;
class function TMid.Name: string;   begin Result := 'mid'; end;
class function TLeaf.Kind: Integer; begin Result := 2; end;
var
  b: TBase;
  cr: TClass;
begin
  { through an INSTANCE typed as the BASE -- must dispatch on the RUNTIME class }
  b := TBase.Create; writeln('base inst : ', b.Kind, ' ', b.Name);
  b := TMid.Create;  writeln('mid  inst : ', b.Kind, ' ', b.Name);
  b := TLeaf.Create; writeln('leaf inst : ', b.Kind, ' ', b.Name, '  (Name inherited from TMid)');
  { named class -- static receiver, still the right body }
  writeln('named     : ', TBase.Kind, ' ', TMid.Kind, ' ', TLeaf.Kind);
end.

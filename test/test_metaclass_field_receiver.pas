{$mode objfpc}{$H+}
{ A metaclass-typed FIELD used as a receiver: `rec.m.Kind`, `rec.m.Create`.

  The parser recognises a metaclass receiver from a LIST of base node kinds --
  a `class of T` variable (AN_IDENT), a metaclass cast (AN_PTR_CAST), an array
  ELEMENT (AN_INDEX, added at b328 for exactly this bug) -- and a record/class
  FIELD was never in it. So `rec.m.Kind` fell through to the plain-pointer
  member path and said

      "Kind": a pointer has no members

  even though the field carries its class in UFldPtrElemTk/UFldPtrElemRec
  exactly as the symbol does in PtrElemTk/PtrElemRec.

  Same list, same omission, one entry later than b328 -- so the controls below
  (variable, array element, parameter) are the spellings that already worked and
  must keep working.

  Every row diffed against FPC.
  bug-a-a-metaclass-typed-record-field-is-not-a-receiver }
program test_metaclass_field_receiver;
type
  TBase = class
    class function Kind: string; virtual;
    constructor Create; virtual;
  end;
  TDer = class(TBase)
    class function Kind: string; override;
    constructor Create; override;
  end;
  TBaseClass = class of TBase;
  TCfg = record m: TBaseClass; n: Integer; end;
  THolder = class public Factory: TBaseClass; end;

var built: string;

class function TBase.Kind: string; begin Result := 'base'; end;
class function TDer.Kind: string;  begin Result := 'der'; end;
constructor TBase.Create; begin inherited Create; built := built + 'B'; end;
constructor TDer.Create;  begin inherited Create; built := built + 'D'; end;

procedure TakesIt(c: TBaseClass); begin WriteLn('param   ', c.Kind); end;

var
  cfg: TCfg; anon: record m: TBaseClass; end;
  arr: array[0..1] of TBaseClass;
  v: TBaseClass;
  h: THolder;
  o: TBase;
begin
  { the controls: spellings that already worked }
  v := TDer;        WriteLn('var     ', v.Kind, ' ', v.ClassName);
  arr[0] := TDer;   WriteLn('element ', arr[0].Kind);
  TakesIt(TDer);

  { the bug: the same value reached through a FIELD }
  cfg.m := TDer; cfg.n := 7;
  WriteLn('named   ', cfg.m.Kind, ' ', cfg.m.ClassName, ' ', cfg.n);
  cfg.m := TBase;
  WriteLn('rebound ', cfg.m.Kind);

  anon.m := TDer;
  WriteLn('anon    ', anon.m.Kind);

  h := THolder.Create;
  h.Factory := TDer;
  WriteLn('classfld ', h.Factory.Kind);

  { construction through a metaclass field dispatches the VIRTUAL constructor }
  built := '';
  o := cfg.m.Create;   { cfg.m is TBase here }
  built := built + '|';
  o.Free;
  o := h.Factory.Create;  { TDer }
  WriteLn('ctor    ', built);
  o.Free;
  h.Free;
  WriteLn('METACLASS FIELD RECEIVER OK');
end.

program esp_obj_class_slots_need_a_class;
{ VMT/IMT/RTTI method slots are DCE roots only while live code can name a
  class (DceClassDataReached). Without -dUSE_CLASS this program names none --
  it has a managed record, whose RTTI finalizes it, and nothing else -- so
  TInterfacedObject's _Release and the interface runtime under it must be
  gone from the object. With -dUSE_CLASS an interface reference keeps them,
  and the program must still print the same as x86-64. }
{$ifdef USE_CLASS}
type
  IGreeter = interface
    function Greet: AnsiString;
  end;
  TGreeter = class(TInterfacedObject, IGreeter)
    function Greet: AnsiString;
  end;

function TGreeter.Greet: AnsiString;
begin
  Result := 'hello from a class';
end;
{$endif}

type
  TReq = record
    Path: AnsiString;
    N: Integer;
  end;

procedure Show(const r: TReq);
begin
  WriteLn(r.Path, ' ', r.N);
end;

var
  r: TReq;
{$ifdef USE_CLASS}
  g: IGreeter;
{$endif}
begin
  r.Path := '/api/state';
  r.N := 7;
  Show(r);
{$ifdef USE_CLASS}
  g := TGreeter.Create;
  WriteLn(g.Greet);
  g := nil;
{$endif}
  WriteLn('done');
end.

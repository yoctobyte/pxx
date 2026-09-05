{ The DECLARING unit for test_generic_body_binds_in_its_declaring_unit.
  `PrivFill` is implementation-private on purpose and the program declares its
  own; which one a template body runs is the whole question. }
unit ugdecl; {$mode objfpc}
interface

procedure IfaceFill;

type
  generic TList<_T> = class(TObject)
    procedure FillPriv;
    procedure FillIface;
  end;
  { the NON-GENERIC control: same shape, same helper, no template }
  TPlain = class(TObject)
    procedure FillPriv;
  end;

procedure RunInUnit;   { the SAME-UNIT specialization control }

implementation

procedure IfaceFill; begin WriteLn('unit iface'); end;
procedure PrivFill;  begin WriteLn('unit priv'); end;

procedure TList.FillPriv;  begin PrivFill; end;
procedure TList.FillIface; begin IfaceFill; end;
procedure TPlain.FillPriv; begin PrivFill; end;

type TSameUnit = specialize TList<Integer>;

procedure RunInUnit;
var l: TSameUnit;
begin l := TSameUnit.Create; l.FillPriv; end;

end.

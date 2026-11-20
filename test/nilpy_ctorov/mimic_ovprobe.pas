unit mimic_ovprobe;
{$MODE PXX}
interface
uses pylib;
type
  K = class
  public
    tag: Integer;
    constructor Create(b: TPyBytes); overload;
    constructor Create(l: TPyList); overload;
  end;
function which(b: TPyBytes): Integer; overload;
function which(l: TPyList): Integer; overload;
implementation
constructor K.Create(b: TPyBytes); begin tag := 1; end;
constructor K.Create(l: TPyList);  begin tag := 2; end;
function which(b: TPyBytes): Integer; begin Result := 1; end;
function which(l: TPyList): Integer;  begin Result := 2; end;
end.

program test_nt_relocation;
{ Every kind of absolute address an image holds, used after the loader has
  had the chance to move it: a VMT slot (virtual call), a procedure pointer,
  a typed constant holding @G, a class name read through RTTI, and an
  exception (the unwinder walks code addresses). test-windows also builds it
  with --image-base=0x7ffe0000, where Windows and Wine must relocate it,
  through the .reloc section pewriter.inc writes. On other targets it is an
  ordinary program with the same output. }
{$mode objfpc}
uses SysUtils;
type
  PInt = ^Integer;
var
  G: Integer = 7;
const
  Ptr: PInt = @G;
type
  TA = class(TObject)
    function Nm: AnsiString; virtual;
  end;
  TB = class(TA)
    function Nm: AnsiString; override;
  end;
  TIntFn = function(x: Integer): Integer;
var
  P: TIntFn;
  a: TA;
function TA.Nm: AnsiString; begin Result := 'TA'; end;
function TB.Nm: AnsiString; begin Result := 'TB'; end;
function Twice(x: Integer): Integer; begin Twice := 2 * x; end;
begin
  P := @Twice;
  WriteLn('proc ptr: ', P(21));
  WriteLn('typed const ptr: ', Ptr^);
  a := TB.Create;
  WriteLn('virtual: ', a.Nm, ' class ', a.ClassName);
  a.Free;
  try
    raise Exception.Create('relocated raise');
  except
    on e: Exception do WriteLn('caught: ', e.Message);
  end;
end.

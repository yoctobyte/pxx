program test_classparent;
{$mode objfpc}{$H+}
uses SysUtils;

type
  TA = class end;
  TB = class(TA) end;
  TC = class(TB) end;
  TAClass = class of TA;
  { A real member of that name must still outrank the class-reference
    operation, exactly as it does for ClassName / InheritsFrom. }
  TShadow = class
    function ClassParent: AnsiString;
  end;

var o: TC; cr: TAClass; p: TClass; sh: TShadow;

function TShadow.ClassParent: AnsiString; begin Result := 'shadowed'; end;

begin
  o := TC.Create;
  WriteLn(o.ClassName);
  WriteLn(o.ClassParent.ClassName);
  WriteLn(o.ClassParent.ClassParent.ClassName);
  WriteLn(BoolToStr(o.ClassParent.ClassParent.ClassParent.ClassName = 'TObject', True));
  WriteLn(BoolToStr(TObject.ClassParent = nil, True));
  cr := TC;
  WriteLn(cr.ClassParent.ClassName);
  p := o.ClassParent;
  WriteLn(p.ClassName, ' ', BoolToStr(o.ClassParent.InheritsFrom(TA), True));
  WriteLn(TC.ClassParent.ClassName);
  o.Free;
  sh := TShadow.Create;
  WriteLn(sh.ClassParent);
  sh.Free;
end.

{$mode objfpc}
program test_a_a_same_arity_ctor_overload_picks_by_class;
type
  TA = class end;
  TB = class end;
  TA2 = class(TA) end;
  K = class
    tag: Integer;
    constructor Create(b: TB); overload;
    constructor Create(a: TA); overload;
  end;
  KR = class
    tag: Integer;
    constructor Create(a: TA); overload;
    constructor Create(a2: TA2); overload;
  end;
constructor K.Create(b: TB); begin tag := 1; end;
constructor K.Create(a: TA); begin tag := 2; end;
constructor KR.Create(a: TA); begin tag := 1; end;
constructor KR.Create(a2: TA2); begin tag := 2; end;
var a: TA; b: TB; a2: TA2;
begin
  a := TA.Create; b := TB.Create; a2 := TA2.Create;
  WriteLn(K.Create(b).tag, ' ', K.Create(a).tag, ' ', K.Create(a2).tag);
  WriteLn(KR.Create(a).tag, ' ', KR.Create(a2).tag);
end.

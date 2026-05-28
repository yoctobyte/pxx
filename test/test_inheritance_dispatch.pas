program test_inheritance_dispatch;
type
  TBase = class
    Val1 : Integer;
    
    constructor Create(v1: Integer);
    procedure   SetVal1(v1: Integer);
    function    GetVal1: Integer; virtual;
    function    Describe: Integer; virtual;
    
    property Value1: Integer read GetVal1 write SetVal1;
  end;

  TDerived = class(TBase)
    Val2 : Integer;
    
    constructor Create(v1: Integer; v2: Integer);
    procedure   SetVal2(v2: Integer);
    function    GetVal2: Integer;
    function    Describe: Integer; override;
    
    property Value2: Integer read GetVal2 write SetVal2;
  end;

constructor TBase.Create(v1: Integer);
begin
  Self.Val1 := v1;
end;

procedure TBase.SetVal1(v1: Integer);
begin
  Self.Val1 := v1;
end;

function TBase.GetVal1: Integer;
begin
  Result := Self.Val1;
end;

function TBase.Describe: Integer;
begin
  Result := Self.Val1 * 10;
end;

constructor TDerived.Create(v1: Integer; v2: Integer);
begin
  Self.Val1 := v1;
  Self.Val2 := v2;
end;

procedure TDerived.SetVal2(v2: Integer);
begin
  Self.Val2 := v2;
end;

function TDerived.GetVal2: Integer;
begin
  Result := Self.Val2;
end;

function TDerived.Describe: Integer;
begin
  Result := Self.Val1 * 100 + Self.Val2;
end;

var
  obj1 : TBase;
  obj2 : TDerived;
  objRef : TBase;
begin
  obj1 := TBase.Create(5);
  obj2 := TDerived.Create(5, 7);
  
  writeln(obj1.Describe); { Should print 50 }
  writeln(obj2.Describe); { Should print 507 }
  
  objRef := obj1;
  writeln(objRef.Describe); { Should print 50 }
  
  objRef := obj2;
  writeln(objRef.Describe); { Should print 507 via virtual method table dispatch! }
  
  writeln(obj1.Value1); { Should print 5 via read property }
  obj1.Value1 := 12;
  writeln(obj1.Value1); { Should print 12 via write property }
  
  writeln(obj2.Value2); { Should print 7 }
  obj2.Value2 := 99;
  writeln(obj2.Value2); { Should print 99 }
  
  writeln(obj2.Value1); { Should print 5 }
  obj2.Value1 := 88;
  writeln(obj2.Value1); { Should print 88 }
end.

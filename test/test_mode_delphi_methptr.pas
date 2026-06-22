{$mode delphi}
program test_mode_delphi_methptr;

{ mode delphi -- @-optional METHOD pointer at the assignment bind site.
  `p := obj.M` (no @) binds a method pointer (the 16-byte Code+Data TMethod)
  exactly like `p := @obj.M`, when p is a `procedure(...) of object` lvalue.
  Both a with-params and a paramless method are covered; a paramless method bare
  on the RHS is the method's ADDRESS (not a call) because the target is a
  method-pointer type. FPC -Mdelphi is the oracle (out: total=12 / kicked=1). }

type
  TEvent = procedure(x: Integer) of object;
  TNotify = procedure of object;

type
  TCounter = class
    total: Integer;
    kicked: Integer;
    procedure Add(x: Integer);
    procedure Kick;
  end;

procedure TCounter.Add(x: Integer);
begin total := total + x; end;

procedure TCounter.Kick;
begin kicked := kicked + 1; end;

var
  c: TCounter;
  e: TEvent;
  n: TNotify;

begin
  c := TCounter.Create;
  c.total := 0;
  c.kicked := 0;

  e := c.Add;          { delphi: no @, with-params method }
  e(5);
  e(7);
  WriteLn('total=', c.total);     { 12 }

  n := c.Kick;         { delphi: no @, paramless method = address, not a call }
  n();
  WriteLn('kicked=', c.kicked);   { 1 }
end.

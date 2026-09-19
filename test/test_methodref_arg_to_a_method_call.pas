program test_methodref_arg_to_a_method_call;
{ `@obj.Method` passed to a METHOD's TMethod parameter. The free-call paths
  reported an AN_METHODREF argument as tyRecord so it binds a method-pointer
  parameter; the method-call overload selector did not, so
  `Bar.AddButton(t, 'Btn', @h.PickA)` was refused as "(..., Pointer)" and
  test_pcl_tabbar and eliah_ide did not compile. Every spelling below must
  reach the OVERRIDE with the INSTANCE (a Pointer that merely type-checked
  would call with no instance), and the method path must choose the same
  overload as the free path.
  bug-p-the-address-of-a-method-is-typed-pointer-so-it-cannot-match-a-tmethod-parameter }
type
  TNotify = procedure(Sender: TObject) of object;
  TBar = class
    procedure AddP(AOnClick: TMethod);
    procedure Ov(P: Pointer); overload;
    procedure Ov(M: TMethod); overload;
  end;
  TBase = class
    Tag: Integer;
    procedure Pick(Sender: TObject); virtual;
    procedure Wire(b: TBar);
  end;
  TDer = class(TBase)
    procedure Pick(Sender: TObject); override;
  end;
procedure Fire(M: TMethod); var ev: TNotify; begin TMethod(ev) := M; ev(nil); end;
procedure TBar.AddP(AOnClick: TMethod); begin Fire(AOnClick); end;
procedure TBar.Ov(P: Pointer); begin WriteLn('Ov(Pointer)'); end;
procedure TBar.Ov(M: TMethod); begin WriteLn('Ov(TMethod)'); Fire(M); end;
procedure FOv(P: Pointer); overload; begin WriteLn('FOv(Pointer)'); end;
procedure FOv(M: TMethod); overload; begin WriteLn('FOv(TMethod)'); Fire(M); end;
procedure TBase.Pick(Sender: TObject); begin WriteLn('base tag=', Tag); end;
procedure TDer.Pick(Sender: TObject); begin WriteLn('der tag=', Tag); end;
procedure TBase.Wire(b: TBar);
begin
  b.AddP(@Pick);        { bare, implicit Self }
  b.AddP(@Self.Pick);   { qualified Self }
end;
var b: TBar; o: TBase;
begin
  b := TBar.Create; o := TDer.Create; o.Tag := 9;
  b.AddP(@o.Pick);      { virtual through a base-typed var: must reach the override }
  o.Wire(b);
  b.Ov(@o.Pick);
  FOv(@o.Pick);
end.

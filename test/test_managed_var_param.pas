program test_managed_var_param;

{ By-reference (`var`/`out`) managed-string parameters: a callee that assigns or
  concatenates through a `var AnsiString` must update the CALLER's handle, with
  the old handle released and the new one retained — not mutate a local copy.

  The arg is passed as the address of the caller's handle slot (IR_SLOTADDR, not
  IR_LEA, which auto-loads the handle for a managed string); the store derefs
  that address to publish into the caller's slot. Forwarding a `var` string from
  one callee to another, and a 2 M-iteration churn loop, guard against leaks and
  the over-free that a wrong retain/release would cause. }

{$define PXX_MANAGED_STRING}

procedure SetIt(var s: AnsiString);
begin
  s := 'hello';
end;

procedure AppendBang(var s: AnsiString);
begin
  s := s + '!';
end;

procedure Forward(var s: AnsiString);
begin
  { s is itself a by-ref param; passing it on must forward the caller's slot,
    not the address of this frame's slot. }
  AppendBang(s);
end;

procedure SetItOut(out s: AnsiString);
begin
  s := 'hello';
end;

procedure Check(ok: Boolean);
begin
  if ok then writeln(1) else writeln(0);
end;

var
  a: AnsiString;
  i: Integer;
begin
  a := 'OLD';
  SetIt(a);
  Check(a = 'hello');           { assign-through-var updated the caller }

  a := 'OLD';
  SetItOut(a);
  Check(a = 'hello');           { assign-through-out updated the caller }

  AppendBang(a);
  Check(a = 'hello!');          { read+concat+store through var }

  Forward(a);
  Check(a = 'hello!!');         { forwarded var param reaches the caller }

  { Churn: assign + concat through var, 2 M times, must stay flat with no leak
    and no over-free crash. }
  a := '';
  for i := 1 to 2000000 do
  begin
    SetIt(a);
    AppendBang(a);
  end;
  Check(a = 'hello!');
  writeln(Length(a));           { 6 }
end.

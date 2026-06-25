program test_setlength_managed_field;
{ bug-setlength-record-field-via-var-param: SetLength on a managed AnsiString
  field reached through a var parameter / record field / pointer deref now resizes
  in place (was: "SetLength expects an array variable"). Routed through the
  address-based IR_SETLEN_STR -> PXXStrSetLen helper, like dyn-array fields. }
type
  TConn = record Buf: AnsiString; end;
  PConn = ^TConn;

procedure Grow(var c: TConn; n: Integer);
var i, old: Integer;
begin
  old := Length(c.Buf);
  SetLength(c.Buf, old + n);          { string field via var param }
  for i := old + 1 to old + n do c.Buf[i] := 'x';
end;

var
  cc: TConn;
  pc: PConn;
  s: AnsiString;
  i: Integer;
begin
  cc.Buf := 'AB';
  Grow(cc, 3);
  writeln(cc.Buf);                    { ABxxx }
  SetLength(cc.Buf, 2);               { direct record field }
  writeln(cc.Buf);                    { AB }
  pc := @cc;
  SetLength(pc^.Buf, 1);              { field via pointer deref }
  writeln(pc^.Buf);                   { A }
  s := 'Q';
  SetLength(s, 3);                    { plain var (symbol path) }
  for i := 2 to 3 do s[i] := 'z';
  writeln(s);                         { Qzz }
end.

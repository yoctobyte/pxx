program test_class_var_of_a_managed_type;
{ A `class var` whose type is a DYNAMIC ARRAY or a POINTER, reached through the
  QUALIFIED spelling (TClass.V) rather than a bare name inside a method.

  SetLength and New both resolve their operand's symbol themselves before handing
  it to the lvalue parser. The qualified form makes that lookup answer the CLASS,
  not the member, so SetLength fell through to its STRING arm and wrote a string
  header over the array handle (compiled clean, segfaulted on the next read) and
  New reported "undefined variable" on a perfectly good pointer. Both now read the
  symbol off the lvalue the parser already resolved.

  Oracle: fpc 3.2.2 -Mobjfpc -O1 produces this output line for line. }
{$mode objfpc}{$H+}
type
  TR = record A, B: Integer; end;
  PR = ^TR;
  TDyn = array of Integer;

  TBase = class
  public class var
    Inl: array of Integer;   { inline dynamic }
    Nmd: TDyn;               { named dynamic }
    Ptr: PR;
    S:   string;
  end;
  TDer = class(TBase)
  end;

var
  o: TBase;
  i, fails: Integer;

procedure Chk(const what: string; got, want: Integer);
begin
  if got <> want then
  begin
    writeln('FAIL ', what, ': got ', got, ' want ', want);
    Inc(fails);
  end;
end;

procedure ChkS(const what, got, want: string);
begin
  if got <> want then
  begin
    writeln('FAIL ', what, ': got "', got, '" want "', want, '"');
    Inc(fails);
  end;
end;

begin
  fails := 0;

  { inline dynamic array: SetLength must allocate an ARRAY, not a string }
  SetLength(TBase.Inl, 3);
  TBase.Inl[0] := 10;
  TBase.Inl[2] := 30;
  Chk('inl len', Length(TBase.Inl), 3);
  Chk('inl[0]', TBase.Inl[0], 10);
  Chk('inl[1]', TBase.Inl[1], 0);
  Chk('inl[2]', TBase.Inl[2], 30);

  { named dynamic array type }
  SetLength(TBase.Nmd, 2);
  TBase.Nmd[1] := 7;
  Chk('nmd len', Length(TBase.Nmd), 2);
  Chk('nmd[1]', TBase.Nmd[1], 7);

  { pointer class var through New/Dispose }
  New(TBase.Ptr);
  TBase.Ptr^.A := 4;
  TBase.Ptr^.B := 5;
  Chk('ptr.A', TBase.Ptr^.A, 4);
  Chk('ptr.B', TBase.Ptr^.B, 5);
  Dispose(TBase.Ptr);

  { a string class var still takes the string arm }
  SetLength(TBase.S, 3);
  TBase.S[1] := 'a';
  TBase.S[2] := 'b';
  TBase.S[3] := 'c';
  ChkS('str', TBase.S, 'abc');
  Chk('str len', Length(TBase.S), 3);

  { a descendant names the SAME slot }
  Chk('der len', Length(TDer.Inl), 3);
  Chk('der[2]', TDer.Inl[2], 30);
  SetLength(TDer.Nmd, 4);
  Chk('der resized base', Length(TBase.Nmd), 4);

  { and so does an instance }
  o := TBase.Create;
  Chk('obj len', Length(o.Inl), 3);
  Chk('obj[0]', o.Inl[0], 10);
  o.Free;

  { the handle survives a loop over it }
  i := 0;
  for i := 0 to Length(TBase.Inl) - 1 do
    Inc(fails, 0);

  if fails = 0 then
    writeln('ALL OK')
  else
    writeln('FAILURES: ', fails);
end.

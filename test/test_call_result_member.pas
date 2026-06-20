program test_call_result_member;

{ Member access on a function/method call result: f(args).field, obj.M(args).field,
  bare implicit-Self M.field, for record- and class-returning callees. The
  postfix parser now continues `.field` / `[i]` selectors after a call primary
  (function, static method, instance method), and IR lowering materialises a
  record-returning call's result into a hidden temp so its field address is
  available (a class result is already a pointer value). }

{$define PXX_MANAGED_STRING}

type
  TRec = record
    Name: AnsiString;
    Q: Integer;
  end;

  TItem = class
    Tag: AnsiString;
  end;

  TBox = class
    R: TRec;
    function GetR: TRec;          { instance method, record result }
    function MakeItem: TItem;     { instance method, class result }
    function Describe: AnsiString;
  end;

function TBox.GetR: TRec;
begin
  Result := R;
end;

function TBox.MakeItem: TItem;
begin
  Result := TItem.Create;
  Result.Tag := 'tag:' + R.Name;
end;

function TBox.Describe: AnsiString;
begin
  { bare implicit-Self method call result .field, both record and class }
  Result := GetR.Name + '/' + MakeItem.Tag;
end;

function MakeRec(n: Integer): TRec;   { free function, record result }
begin
  Result.Name := 'rec';
  Result.Q := n;
end;

var
  b: TBox;
begin
  b := TBox.Create;
  b.R.Name := 'hello';
  b.R.Q := 42;

  { free function result .field — with arg and (Q) second field }
  Writeln(MakeRec(7).Name);     { rec }
  Writeln(MakeRec(7).Q);        { 7 }

  { qualified instance-method result .field — record and class }
  Writeln(b.GetR.Name);         { hello }
  Writeln(b.GetR.Q);            { 42 }
  Writeln(b.MakeItem.Tag);      { tag:hello }

  { bare implicit-Self method results inside a method }
  Writeln(b.Describe);          { hello/tag:hello }
end.

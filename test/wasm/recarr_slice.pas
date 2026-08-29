{ `a[i].Field` where a is a DYNAMIC ARRAY OF RECORDS.

  The base of such an index is an IR_DYNUNIQUE node, and that node's type kind
  names the ELEMENT — so an `array of TRec` produced a record-typed node whose
  value has always been a plain i32 data pointer. Read as the node's own type
  it looks like a record on the operand stack, which is what `value of type
  record in array base` was saying. The identical statement on an
  `array of Integer` worked throughout, which is what made it look like a
  record problem rather than a type-kind problem.

  Same misreading one level along from `Length of Pointer`: a diagnostic
  naming the type of a node it did not recognise, correctly, and pointing
  away from the fix.

  The shape is not exotic — it is `list.Items[list.Count].Off := o`, the growable
  array-of-structs every one of lib/asmcore's five encoders is built on, which
  is why three compiler.pas bodies stopped here. }
program RecArrSlice;

type
  TItem = record
    Off: Integer;
    W: Integer;
  end;
  TItems = array of TItem;
  TList = record
    Items: TItems;
    Count: Integer;
  end;

  TNamed = record
    Name: string;
    N: Integer;
  end;
  TNames = array of TNamed;

procedure Add(var list: TList; o, w: Integer);
begin
  if list.Count >= Length(list.Items) then
    SetLength(list.Items, list.Count * 2 + 4);
  list.Items[list.Count].Off := o;
  list.Items[list.Count].W := w;
  Inc(list.Count);
end;

procedure BumpVar(var it: TItem);
begin
  it.Off := it.Off + 100;
end;

var
  L: TList;
  ns: TNames;
  one: TItem;
  i, sum: Integer;

begin
  { The asmcore shape: grow-on-demand, write two fields through the index. }
  for i := 1 to 9 do Add(L, i * 10, i);
  writeln('count  ', L.Count, ' ', Length(L.Items) >= 9);
  writeln('read   ', L.Items[0].Off, ' ', L.Items[4].Off, ' ', L.Items[8].W);

  { Growth must preserve what was already written — the reallocation copies
    whole records, not handles. }
  writeln('kept   ', L.Items[0].Off, ' ', L.Items[3].W);

  { A computed index, so the address is not a constant fold. }
  i := 2;
  writeln('comp   ', L.Items[i * 3].Off);

  { A whole element read OUT into a record variable, and one written back in:
    a record copy whose source or destination is a heap element. }
  one := L.Items[5];
  one.Off := 999;
  L.Items[1] := one;
  writeln('copy   ', L.Items[1].Off, ' ', L.Items[1].W, ' ', L.Items[5].Off);

  { An element passed as a VAR parameter — the callee writes through the
    element's address, so nothing may have been copied on the way in. }
  BumpVar(L.Items[2]);
  writeln('varel  ', L.Items[2].Off);

  { An array of records with a MANAGED field. The element stride is the whole
    record and the string inside it is published like any other, so this is
    where a stride computed from the handle rather than the record would show. }
  SetLength(ns, 3);
  ns[0].Name := 'alpha'; ns[0].N := 1;
  ns[1].Name := 'beta';  ns[1].N := 2;
  ns[2].Name := 'gamma'; ns[2].N := 3;
  writeln('named  ', ns[0].Name, ' ', ns[1].Name, ' ', ns[2].Name, ' ', ns[2].N);
  ns[1].Name := 'BETA';
  writeln('rewrit ', ns[0].Name, ' ', ns[1].Name, ' ', ns[2].Name);

  sum := 0;
  for i := 0 to L.Count - 1 do sum := sum + L.Items[i].W;
  writeln('sum    ', sum);
  writeln('done');
end.

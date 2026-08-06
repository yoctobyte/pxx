{$define PXX_MANAGED_STRING}
program test_dynarray_managed_record;

type
  TInner = record
    Text: AnsiString;
  end;

  TEntry = record
    Inner: TInner;
    LabelText: AnsiString;
    Value: Integer;
  end;

var
  a: array of TEntry;
  b: array of TEntry;

procedure Check(ok: Boolean);
begin
  if ok then
    writeln(1)
  else
    writeln(0);
end;

procedure TestLocal;
var
  local: array of TEntry;
begin
  SetLength(local, 1);
  local[0].Inner.Text := 'local';
  local[0].LabelText := 'label';
  Check(local[0].Inner.Text = 'local');
  Check(local[0].LabelText = 'label');
end;

begin
  SetLength(a, 2);
  a[0].Inner.Text := 'one';
  a[0].LabelText := 'zero';
  a[0].Value := 10;
  a[1].Inner.Text := 'two';
  Check(a[0].Inner.Text = 'one');
  Check(a[0].LabelText = 'zero');
  Check(a[0].Value = 10);

  { Aliased, and the element being a RECORD with managed fields changes nothing:
    the array data is shared, so writing b[0]'s fields writes a[0]'s. Asserted
    the copy-on-write answer ('one' / 'zero') until 2026-08-06; measured against
    an FPC build of this exact record shape, which prints 'changed' through both
    (bug-a-x86-64-dynarray-assignment-copies-instead-of-aliasing). }
  b := a;
  b[0].Inner.Text := 'changed';
  b[0].LabelText := 'changed-label';
  Check(a[0].Inner.Text = 'changed');
  Check(a[0].LabelText = 'changed-label');
  Check(b[0].Inner.Text = 'changed');
  Check(b[0].LabelText = 'changed-label');

  SetLength(b, 4);
  Check(b[0].Inner.Text = 'changed');
  Check(b[1].Inner.Text = 'two');
  Check(b[3].Inner.Text = '');
  b[3].LabelText := 'new';
  Check(b[3].LabelText = 'new');

  SetLength(b, 1);
  Check(b[0].Inner.Text = 'changed');
  Check(a[1].Inner.Text = 'two');
  TestLocal;
  SetLength(a, 0);
  SetLength(b, 0);
  Check(Length(a) = 0);
  Check(Length(b) = 0);
end.

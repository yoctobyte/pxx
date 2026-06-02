{$define PXX_MANAGED_STRING}
program test_dynarray_managed_record_assign_error;

type
  TManaged = record
    Text: AnsiString;
  end;

var
  a: TManaged;
  b: TManaged;

begin
  a := b;
end.

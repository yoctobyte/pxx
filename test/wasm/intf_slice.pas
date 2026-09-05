program intf_slice;
{ An interface value is a single instance pointer, and it is spelled tyRecord
  everywhere in the type system. Reading one THROUGH AN ADDRESS — a record
  field, a pointer deref — is the shape that made every backend guess what a
  record-typed load means, because for a real aggregate the value IS the
  address and for an interface the address is where the pointer LIVES.

  Each row prints something that is wrong in a DIFFERENT way if the load is
  skipped: an address is non-nil too, so `<> nil` alone cannot see it. The
  round trip through the interface is what proves the pointer is real. }
type
  IFoo = interface
    function Val: Integer;
  end;
  TFoo = class(TInterfacedObject, IFoo)
    F: Integer;
    function Val: Integer;
  end;
  TRec  = record I: IFoo; N: Integer; end;
  PRec  = ^TRec;

function TFoo.Val: Integer;
begin
  Val := F;
end;

var
  r: TRec;
  p: PRec;
  ptr: Pointer;
  o: TFoo;
  ifv, back: IFoo;
begin
  o := TFoo.Create;
  o.F := 42;
  ifv := o;
  r.I := ifv;
  r.N := 7;

  { the ticket's own repro: an interface-valued FIELD read into a Pointer }
  ptr := r.I;
  writeln('ptr-nonnil=', ptr <> nil);

  { the round trip — a skipped load yields the field's ADDRESS, which is also
    non-nil and would call through garbage or answer the wrong number }
  back := r.I;
  writeln('roundtrip=', back.Val);

  { through a POINTER to the record, the same read one indirection along }
  p := @r;
  back := p^.I;
  writeln('via-ptr=', back.Val);

  { the neighbouring field must be untouched — a wrong width here would smear }
  writeln('neighbour=', r.N);

  { calling straight off the field read, with no intermediate variable }
  writeln('direct=', r.I.Val);
end.

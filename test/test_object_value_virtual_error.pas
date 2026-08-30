{ An `object` method cannot be virtual. Same reason as the ancestor test: no
  VMT. `dynamic`, `override` and `abstract` take the identical path and produce
  the identical diagnostic with their own keyword in it; this file pins
  `virtual` as the representative.

  The point is that it is a DIAGNOSTIC. A record has no VMT either, so the
  directive is not in the record method-directive loop at all -- it falls out
  and gets misread as the next field, which is the confusing failure this
  refusal exists to replace. bug-p-object-value-types-standard-meaning }
program test_object_value_virtual_error;
type
  TThing = object
    procedure Speak; virtual;
  end;
procedure TThing.Speak; begin end;
var t: TThing;
begin
  t.Speak;
end.

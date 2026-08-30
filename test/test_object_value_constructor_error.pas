{ An `object` type cannot have a constructor (or a destructor -- same path, same
  diagnostic with its own keyword).

  This one has to be an EXPLICIT refusal rather than an omission: the record
  machinery underneath would happily take `constructor`, so without this check
  it would parse, compile, and silently do none of the thing it was written to
  do. In an old-style object a constructor's job is to set the VMT pointer that
  `virtual` dispatch reads, and pxx's `object` has no VMT.
  bug-p-object-value-types-standard-meaning }
program test_object_value_constructor_error;
type
  TThing = object
    X: Integer;
    constructor Init(ax: Integer);
  end;
constructor TThing.Init(ax: Integer); begin X := ax; end;
var t: TThing;
begin
  t.Init(3);
end.

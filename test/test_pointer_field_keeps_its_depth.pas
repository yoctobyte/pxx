program test_pointer_field_keeps_its_depth;
{ A `^PChar` FIELD -- of a record and of a class -- keeps the whole pointer
  shape, so `r.F^` is a PChar and `r.F^[i]` is a Char, exactly as the same type
  behaves in a variable, a parameter, a capture and a function result.

  The record-field arm of the deref chain read UFldPtrElemTk/Rec -- the
  immediate pointee -- and nothing beside it, so a `^PChar` field and a `PChar`
  field were indistinguishable: WriteLn printed the address, concat on either
  side yielded the address, and `=` compared pointers. The three contexts that
  looked right were right only by the blanket AnsiString(<any pointer>) rule,
  which is the signature this whole family kept showing.

  .expected IS fpc 3.2.2's own output on this source.
  bug-p-dereferencing-a-function-result-of-pointer-to-pchar-loses-the-shape }
{$mode objfpc}
type
  PPChar = ^PChar;

  TRec = record
    F: PPChar;
  end;

  TBox = class
    F: PPChar;
  end;

var
  p0: PChar;
  q: PPChar;
  r: TRec;
  b: TBox;

begin
  p0 := 'alpha';
  q := @p0;
  r.F := q;
  b := TBox.Create;
  b.F := q;
  WriteLn('recfield: ', r.F^);
  WriteLn('clsfield: ', b.F^);
  WriteLn('recindex: ', r.F^[1], r.F^[4]);
  WriteLn('clsindex: ', b.F^[1]);
  WriteLn('concatL : ', 'x' + r.F^);
  WriteLn('concatR : ', r.F^ + 'y');
  WriteLn('equal   : ', r.F^ = 'alpha');
  WriteLn('notequal: ', b.F^ <> 'alpha');
  WriteLn('length  : ', Length(AnsiString(r.F^)));
end.

program test_methodptr_nil_assign;
{ `OnClick := nil` — how you DETACH an event handler — SEGFAULTED at the store,
  before any call, in a program with no unsafe construct in it.

  A method pointer (`procedure(...) of object`) is a 16-byte {Code,Data} record,
  and `nil` is an AN_INT_LIT 0 typed tyPointer, so the assignment fell through to
  the whole-record copy and emitted `rep movsb` READING FROM ADDRESS 0. The
  interface arm one `if` above it had exactly this fixed, with a comment saying
  "the RHS is a pointer/ordinal nil ... it never reaches the record-copy path
  (which would dereference a bogus source)". The sibling was not checked —
  devdocs/dev/normalise-dont-special-case.md, and the arm that stayed broken is
  the one people write.

  FOUR SHAPES, because a fix that only covers the simple variable store leaves
  the common case broken: a variable, a FIELD (`c.OnHit := nil`, which is what
  event-handler code actually does), an ARRAY ELEMENT, and a `var` parameter
  nilled by the callee. Each is re-armed and CALLED first, so the test also
  proves the slot was working before it was cleared and that Assigned() is
  reading a real value rather than always-false.
  bug-a-assigning-nil-to-a-method-pointer-segfaults }
type
  TEv = procedure(x: Integer) of object;
  TC = class
    OnHit: TEv;
    procedure Hit(x: Integer);
  end;

procedure TC.Hit(x: Integer); begin writeln('hit ', x); end;
procedure TakeVar(var e: TEv); begin e := nil; end;

var
  ev: TEv;
  c: TC;
  arr: array[0..2] of TEv;
  i: Integer;
begin
  c := TC.Create;

  ev := @c.Hit;
  ev(1);
  ev := nil;
  writeln('var    assigned=', Assigned(ev));

  c.OnHit := @c.Hit;
  c.OnHit(2);
  c.OnHit := nil;
  writeln('field  assigned=', Assigned(c.OnHit));

  arr[1] := @c.Hit;
  arr[1](3);
  arr[1] := nil;
  writeln('elem   assigned=', Assigned(arr[1]));

  ev := @c.Hit;
  TakeVar(ev);
  writeln('varpar assigned=', Assigned(ev));

  for i := 0 to 2 do arr[i] := nil;
  writeln('loop ok');
end.

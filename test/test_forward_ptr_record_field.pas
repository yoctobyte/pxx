{ Forward pointer type + record member access.

  `PNode = ^TNode` ahead of TNode is the classic linked-list idiom. The field
  `next: PNode` inside TNode captured its pointee record BEFORE
  ResolvePendingPointerAliases learned what TNode was, so it kept REC_NONE and
  every field reached through a deref of it resolved at OFFSET 0.

  `p^.next^.v` still looked right — v IS at offset 0 — which is exactly what hid
  the bug. Only a SECOND field read back the wrong slot: `p^.next^.next` returned
  v (42) instead of nil.

  Also covers the two members of the same family:
    - implicit deref: `p.v` means `p^.v` (FPC/Delphi). It used to resolve the
      field at an offset into the POINTER VALUE and print garbage.
    - a plain Pointer has no members at all: `q.Anything` is now an error
      (see test/fail_ptr_member_access.pas). }
program test_forward_ptr_record_field;

type
  PNode = ^TNode;
  TNode = record
    v: Integer;
    next: PNode;
  end;

var
  a, b, c: TNode;
  p: PNode;
  fails: Integer;

procedure Check(const what: AnsiString; got, want: Int64);
begin
  if got = want then
    writeln('ok   ', what, ' = ', got)
  else
  begin
    writeln('FAIL ', what, ' = ', got, ' (want ', want, ')');
    fails := fails + 1;
  end;
end;

begin
  fails := 0;

  c.v := 3; c.next := nil;
  b.v := 42; b.next := @c;
  a.v := 7;  a.next := @b;
  p := @a;

  { one deref: worked before, still works }
  Check('p^.v', p^.v, 7);

  { chained deref through the forward-declared pointer field. The FIRST field of
    the pointee (offset 0) accidentally worked even when the record id was lost. }
  Check('p^.next^.v', p^.next^.v, 42);

  { ...and the second one did not: this returned 42 (the v slot) instead of @c. }
  Check('p^.next^.next^.v', p^.next^.next^.v, 3);
  Check('p^.next^.next^.next = nil', Ord(p^.next^.next^.next = nil), Ord(True));
  Check('p^.next^.next <> nil', Ord(p^.next^.next <> nil), Ord(True));

  { implicit deref: p.v is p^.v }
  Check('p.v', p.v, 7);
  Check('p.next^.v', p.next^.v, 42);

  { writing through the chain lands in the right slot too }
  p^.next^.v := 99;
  Check('b.v after p^.next^.v := 99', b.v, 99);
  p.next^.next^.v := 5;
  Check('c.v after p.next^.next^.v := 5', c.v, 5);

  if fails = 0 then writeln('PASS') else writeln('FAILED ', fails);
end.

program afpa;
{$mode objfpc}
{ AN ALIAS OF A FORWARD POINTER ALIAS MUST GET ITS POINTEE.

    PItem = ^TItem;                        { forward: TItem not declared yet }
    TItem = record data: Integer; next: PItem; end;
    TIter = PItem;                         { copies REC_NONE and kept it }

  TIer took its pointer triple from PItem while PItem was still the unresolved
  forward half, and ResolvePendingPointerAliases — which repairs PItem at the
  end of the type section — finds its rows by TARGET NAME, which only the
  `X = ^T` spelling recorded. So this row was invisible to the repair and kept
  REC_NONE for the life of the program.

  EVERY ROW HERE READS A SECOND FIELD, deliberately. The failure is offset-0
  shaped: `it^.data` is CORRECT through the broken row because data sits at
  offset 0, so a test that read only the first field passes either way and
  certifies the bug. `it^.next` is the field that moves.

  Rows C and D are the controls that used to work — a separate type section
  (the repair has run) and no forward at all — so a regression that broke
  pointer aliases generally cannot hide as a pass here. }
type
  PItem = ^TItem;
  TItem = record data: Integer; next: PItem; end;
  TIter = PItem;
type
  TLate = PItem;              { C: separate section, PItem already repaired }
type
  TNode = record v: Integer; nxt: ^TNode; end;
  PNode = ^TNode;
  TNodeIter = PNode;          { D: no forward — TNode was complete first }
var
  a, b: PItem; it: TIter; late: TLate;
  n1, n2: PNode; ni: TNodeIter;
begin
  New(a); a^.data := 10; a^.next := nil;
  New(b); b^.data := 11; b^.next := a;
  write('A');  write(b^.next^.data);          { direct PItem — always worked }
  it := b;
  write(' B'); write(it^.next^.data);         { THE BUG: refused, or wrong slot }
  late := b;
  write(' C'); write(late^.next^.data);
  New(n1); n1^.v := 20; n1^.nxt := nil;
  New(n2); n2^.v := 21; n2^.nxt := n1;
  ni := n2;
  write(' D'); write(ni^.nxt^.v);
  { and one STEP through the alias — this shape compiled even when broken and
    segfaulted on the next deref, so it fails differently from the rows above. }
  it := it^.next;
  write(' E'); writeln(it^.data);
end.

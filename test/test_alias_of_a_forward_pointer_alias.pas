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
type
  TFix = array[0..1] of TIter;   { F: named array type, pointer element }
  TDyn = array of TIter;         { G: same, dynamic }
var
  a, b: PItem; it: TIter; late: TLate;
  n1, n2: PNode; ni: TNodeIter;
  fix: TFix; dyn: TDyn;
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
  write(' E'); write(it^.data);
  { THE SAME SNAPSHOT, IN THE OTHER TWO STORAGE LOCATIONS. One concept — "a
    pointee copied out of an alias that was not resolved yet" — is stored three
    times: on the alias row, on a record FIELD, and on a named ARRAY TYPE's
    element. The repair pass had loops for the first two, so fixing the alias
    row left `array[..] of TIter` still blank while `record cur: TIter end` was
    already right. Both array flavours, because dynamic and fixed take different
    element paths. }
  SetLength(dyn, 2); dyn[0] := b;
  fix[0] := b;
  write(' F'); write(fix[0]^.next^.data);
  write(' G'); writeln(dyn[0]^.next^.data);
end.

program test_cast_deref_chain_siblings;
{ The siblings of bug-p-a-second-deref-on-a-typecast-pointer-field-is-dropped,
  checked before that ticket was closed rather than after the next report.

  The fix was not made at the call site — it extended the shared NodePtrElem
  predicate with the two spellings it did not know (a pointer FIELD and an
  inline PTR_CAST), so every chain that reaches a `^` through those now answers
  from the node the `^` is applied to. These are the chains that proves it
  reaches further than the one reported shape: a doubly-nested `^.^.^`, and a
  deref of an ELEMENT of a pointer array field (which arrives via the INDEX arm
  and then the new FIELD arm). Length() and a concatenation are here because
  both put the derefed value in a different context than Writeln does.

  Every row diffed against FPC 3.2.2. }
type
  PStr   = ^string;
  PInner = ^TInner;
  TInner = record s: PStr; end;
  TRec   = record k: Int64; n: PStr; inr: PInner; arr: array[0..2] of PStr; end;
  PRec   = ^TRec;
var r: TRec; ii: TInner; s, s2: string; raw: Pointer;
begin
  s := 'hello'; s2 := 'world';
  ii.s := @s2; r.k := 42; r.n := @s; r.inr := @ii;
  r.arr[0] := @s; r.arr[1] := @s2;
  raw := @r;
  Writeln('a nested ^.^.^  : ', PRec(raw)^.inr^.s^);
  Writeln('b field arr[i]^ : ', PRec(raw)^.arr[1]^);
  Writeln('c len of deref  : ', Length(PRec(raw)^.n^));
  Writeln('d concat        : ', PRec(raw)^.n^ + '!');
  Writeln('e nested field  : ', PRec(raw)^.inr^.s^ + '?');
end.

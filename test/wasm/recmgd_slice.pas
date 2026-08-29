{ ARC-correct whole-record copy — IR_COPY_REC_MANAGED.

  A record that owns managed fields cannot be copied with a byte move: the
  destination's old references must be dropped and the source's must be
  retained, or the copy is a double-free waiting to happen at one end and a
  leak at the other. Neither shows up in output, which is why this slice is
  paired with a check that measures the heap and a check that outlives its
  source rather than only diffing what gets printed.

  THE ORDER IS THE CORRECTNESS: retain the source before releasing the
  destination, so `a := a` and two records sharing a field net zero. The
  self-assignment row is not a curiosity — it is the row that fails if the two
  are swapped, and it fails by printing an empty string, not by crashing.

  ABSENT AND NAMED: a FUNCTION whose result is a managed record. It refuses
  with `compiler error: EmitZeroFrameSlot: unhandled target` — the LOUD arm of
  bug-a-emitzeroframeslot-has-no-wasm32-arm, a Track A ticket this lane cannot
  fix — long before the copy op is reached, so including it would make this
  slice red for something that is not its subject. The copy path it would have
  added (a callee-built record copied out through the hidden destination) is
  therefore untested here and is named again at the bottom of the check. }
program RecMgdSlice;

type
  TRow = array of Integer;
  TR = record
    S: string;
    A: TRow;
    N: Integer;
  end;
  TInner = record
    S: string;
    K: Integer;
  end;
  TOuter = record
    Inner: TInner;
    Tag: string;
  end;
  TRs = array of TR;

procedure ShowVal(r: TR);
begin
  writeln('byval   ', r.S, ' ', Length(r.A), ' ', r.N);
end;

var
  a, b, c: TR;
  o, o2: TOuter;
  rs: TRs;
  i: Integer;

begin
  a.S := 'hello';
  SetLength(a.A, 3);
  for i := 0 to 2 do a.A[i] := i + 1;
  a.N := 7;

  b := a;
  writeln('assign  ', b.S, ' ', Length(b.A), ' ', b.N, ' ', b.A[2]);

  { Self-assignment. Retain-before-release is what makes this print `hello`
    rather than an empty string over a freed block. }
  a := a;
  writeln('self    ', a.S, ' ', Length(a.A), ' ', a.N);

  ShowVal(a);

  { The destination already OWNS something. Its old references must be dropped
    here and nowhere else — this is the row the leak probe measures in bulk. }
  c.S := 'discarded';
  SetLength(c.A, 9);
  c := a;
  writeln('overw   ', c.S, ' ', Length(c.A));

  { The copy must outlive its source. If the source's fields were not retained,
    everything below reads freed memory — and reads it as plausible data, which
    is why this row exists rather than a comment saying the retain is there. }
  b := a;
  a.S := 'changed';
  SetLength(a.A, 0);
  writeln('outlive ', b.S, ' ', Length(b.A), ' ', b.A[1]);

  { A record whose managed field is inside a NESTED record: the walk recurses,
    and a copy that only looked at the top level would print an empty tag. }
  o.Inner.S := 'nested';
  o.Inner.K := 4;
  o.Tag := 'tag';
  o2 := o;
  o.Inner.S := 'gone';
  writeln('nested  ', o2.Inner.S, ' ', o2.Inner.K, ' ', o2.Tag);

  { A record copied INTO an element of a dynamic array — the destination is a
    heap address rather than a frame slot, which is a different address path
    into the same op. }
  SetLength(rs, 2);
  rs[0] := a;
  rs[1].S := 'elem';
  SetLength(rs[1].A, 5);
  rs[1].N := 5;
  writeln('elem    ', rs[1].S, ' ', Length(rs[1].A), ' ', rs[1].N);
  writeln('done');
end.

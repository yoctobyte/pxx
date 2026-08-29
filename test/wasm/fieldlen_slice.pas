{ Length of a dynamic-array handle that lives in a SLOT rather than in a named
  variable — a record/class FIELD, or an element of a static array of rows.

  Both shapes reach Length as a node whose IR type is `Pointer`, which is why
  this target's refusal message read `Length of Pointer` for a year: the
  message was never about pointers, it was this shape going unrecognised. The
  two node kinds are IR_FIELD and IR_INDEX and both are exercised here — P1
  below lowers through `index ... tk=17` and P2 through `field ... tk=17`,
  measured with PXXDBG rather than assumed, because a slice that happens to
  route both cases through one arm would look like coverage and be one test.

  The nil rows are the point of the guard, not decoration: a field that was
  declared and never SetLength holds nil, `Length` of it is legal Pascal, and
  the answer is 0 — without the guard the load reads address -8.

  A record passed BY VALUE is deliberately absent, and named rather than
  dropped: `ShowValRec(b: TBuf)` refuses with `statement IR op 46`
  (IR_COPY_REC_MANAGED), because copying a record that owns managed fields is
  a different feature — retaining each managed field of the copy — that this
  arm neither needs nor provides. Its var and const forms are here; adding the
  by-value one would have made this slice fail for a reason that is not its
  subject, which is how a slice stops being a slice. }
program FieldLenSlice;

type
  TRow  = array of Integer;
  TStrs = array of string;
  TGrid = array[0..2] of TRow;
  TBuf  = record
    Bytes: TRow;
    Names: TStrs;
    N: Integer;
  end;
  TBufs = array of TBuf;
  TM    = array of array of Integer;

  THolder = class
    Data: TRow;
  end;

procedure ShowVarRec(var b: TBuf);
begin
  writeln('varrec  ', Length(b.Bytes), ' ', Length(b.Names));
end;

procedure ShowConstRec(const b: TBuf);
begin
  writeln('cstrec  ', Length(b.Bytes), ' ', Length(b.Names));
end;

procedure ShowVarGrid(var g: TGrid);
begin
  writeln('vargrid ', Length(g[0]), ' ', Length(g[1]), ' ', Length(g[2]));
end;

var
  b: TBuf;
  e: TBuf;
  g: TGrid;
  h: THolder;
  bs: TBufs;
  m: TM;
  i: Integer;

begin
  SetLength(b.Bytes, 5);
  SetLength(b.Names, 2);
  b.Names[0] := 'alpha';
  b.Names[1] := 'beta';
  b.N := 5;
  writeln('rec     ', Length(b.Bytes), ' ', Length(b.Names));

  { A field never SetLength: nil, and Length of nil is 0, not a fault. }
  writeln('nilrec  ', Length(e.Bytes), ' ', Length(e.Names));

  ShowVarRec(b);
  ShowConstRec(b);

  for i := 0 to 2 do SetLength(g[i], i + 4);
  writeln('grid    ', Length(g[0]), ' ', Length(g[1]), ' ', Length(g[2]));
  ShowVarGrid(g);

  h := THolder.Create;
  writeln('nilcls  ', Length(h.Data));
  SetLength(h.Data, 9);
  writeln('cls     ', Length(h.Data));

  { A record field reached THROUGH an index: FIELD over INDEX, which is a
    different node nest from either arm on its own. }
  SetLength(bs, 2);
  SetLength(bs[0].Bytes, 3);
  SetLength(bs[1].Bytes, 6);
  writeln('idxfld  ', Length(bs[0].Bytes), ' ', Length(bs[1].Bytes));

  { The nested-row case, which already worked through the dyn-array arm. It is
    here as a regression guard, not as new coverage: it and the grid above look
    identical in source and take different arms. }
  SetLength(m, 3);
  for i := 0 to 2 do SetLength(m[i], i * 2 + 1);
  writeln('nested  ', Length(m), ' ', Length(m[0]), ' ', Length(m[1]), ' ', Length(m[2]));

  { Growing through the field: the handle in the slot is replaced, so a Length
    that cached the old one would be caught here and nowhere above. }
  SetLength(b.Bytes, 11);
  writeln('grown   ', Length(b.Bytes));
  SetLength(b.Bytes, 0);
  writeln('emptied ', Length(b.Bytes));

  { The elements must still be readable — a Length that is right while the data
    pointer is wrong would pass everything above. }
  for i := 0 to Length(g[2]) - 1 do g[2][i] := i * 10;
  writeln('read    ', g[2][0], ' ', g[2][3], ' ', g[2][Length(g[2]) - 1]);
  writeln('strs    ', b.Names[0], ' ', b.Names[1]);
  writeln('done');
end.

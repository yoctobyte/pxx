{$define PXX_MANAGED_STRING}
program test_dynarray_copy_expr_source;

{ Copy()'s source need not be a bare NAME. An element of a nested array (`g[0]`)
  and a record field (`r.items`) are both dynamic arrays, and FPC copies either —
  pxx demanded an identifier at both of its Copy lowering sites, because
  AN_DYN_COPY read its element metadata off the source SYMBOL. It now takes it
  from the NODE via NodeDynBaseTk / NodeDynBaseRec, the pair IR_SETLEN_DYN
  already used to support `SetLength(r.items, n)` and `SetLength(a[i], n)`.
  bug-p-copy-rejects-a-dynamic-array-expression-that-is-not-a-bare-name

  This is a SEPARATE file from test_dynarray_copy.pas on purpose. That one is
  wired into the i386 / arm32 / aarch64 / riscv32 differential jobs, and the
  nested-array element source below dies on riscv32 — not on this feature, but on
  bug-a-riscv32-nested-dynamic-array-element-write-segfaults, which predates it
  and reproduces on pinned. Putting these cases there would have turned a
  cross-target job red for an unrelated reason. Fold them in once riscv32 is
  fixed.

  Every value was diffed against an FPC build of this same file. }

type
  TIntArr = array of Integer;
  TFldRec = record items: TIntArr; end;

var
  g: array of array of Integer;
  sg: array of array of AnsiString;
  eb: TIntArr;
  sb: array of AnsiString;
  fr: TFldRec;

begin
  { ELEMENT of a nested array as the source. }
  SetLength(g, 1); SetLength(g[0], 3);
  g[0][0] := 10; g[0][1] := 20; g[0][2] := 30;

  eb := Copy(g[0]);                             { 1-arg whole-array shorthand }
  Writeln(Length(eb), ' ', eb[0], ' ', eb[2]);  { 3 10 30 }
  eb[0] := 99;
  Writeln(g[0][0], ' ', eb[0]);                 { 10 99 — independent }

  eb := Copy(g[0], 1, 2);                       { 3-arg }
  Writeln(Length(eb), ' ', eb[0]);              { 2 20 }

  { RECORD FIELD as the source. }
  SetLength(fr.items, 3);
  fr.items[0] := 7; fr.items[1] := 8; fr.items[2] := 9;

  eb := Copy(fr.items);
  Writeln(Length(eb), ' ', eb[0], ' ', eb[2]);  { 3 7 9 }
  eb[2] := 77;
  Writeln(fr.items[2], ' ', eb[2]);             { 9 77 — independent }

  eb := Copy(fr.items, 2, 1);
  Writeln(Length(eb), ' ', eb[0]);              { 1 9 }

  { MANAGED elements through an element source, so the retain AN_DYN_COPY needs
    for a raw byte copy is exercised on this path too — run under
    -dPXX_HEAP_DEBUG as well, which is the only way a missing retain shows up
    (see test_dynarray_copy_managed_elems.pas). }
  SetLength(sg, 1); SetLength(sg[0], 2);
  sg[0][0] := 'keep'; sg[0][1] := 'also';
  sb := Copy(sg[0]);
  sb[0] := 'REPLACED';
  Writeln(sg[0][0], ' ', sb[0], ' ', sb[1]);    { keep REPLACED also }

  { the second level of a per-level DEEP copy, which is what this unblocks:
    `local[0] := Copy(shared[0])`. The outer `Copy(shared)` is still refused —
    feature-dynarray-copy-nested-element-type — so the deep-copy idiom is not
    complete yet, only this half of it. }
  SetLength(sb, 0);
  sb := Copy(sg[0]);
  sb[1] := 'SECOND';
  Writeln(sg[0][1], ' ', sb[1]);                { also SECOND }
end.

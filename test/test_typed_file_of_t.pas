program test_typed_file_of_t;
{ `file of T` and untyped `file` — the classic Pascal persistence idiom.
  feature-pascal-typed-and-untyped-files

  EVERY EXPECTATION BELOW IS FPC 3.2.2's OWN OUTPUT for this same program,
  measured, not reasoned about — and the last row is the one that matters most:
  the two compilers' files are compared BYTE FOR BYTE, so a divergence in the
  on-disk layout cannot hide behind agreeing values. A test that only read back
  what it wrote would pass on any self-consistent format.

  Positions and counts are in RECORDS, never bytes. `pos` after one Read of a
  `file of Integer` is 1, not 4, and FileSize of a five-element file is 5. That
  is the whole difference between this surface and a raw byte handle, and the
  rows below assert it in both directions (Seek then FilePos, FilePos then
  FileSize). }
{$MODE OBJFPC}
uses sysutils;

type
  TRec = record
    a: Integer;
    b: Double;
    c: array[0..3] of Byte;
  end;
  TIntFile = file of Integer;

var
  tmpdir: string;
  pathI, pathR, pathU: string;
  ok, tot: Integer;

procedure Chk(const nm: string; got, want: Int64);
begin
  tot := tot + 1;
  if got = want then begin ok := ok + 1; writeln('ok   ', nm); end
  else writeln('FAIL ', nm, ' = ', got, ' want ', want);
end;

procedure ChkB(const nm: string; got, want: Boolean);
begin
  tot := tot + 1;
  if got = want then begin ok := ok + 1; writeln('ok   ', nm); end
  else writeln('FAIL ', nm, ' = ', got, ' want ', want);
end;

{ A `var f: TIntFile` PARAMETER — the named-alias half of the feature. The
  element width has to survive the alias AND the parameter list, and a
  parameter is where it is most likely not to: the allocation loop runs after
  every parameter's type is parsed. }
procedure FillInts(var f: TIntFile; n: Integer);
var i: Integer;
begin
  Rewrite(f);
  for i := 1 to n do Write(f, i * 10);
end;

var
  fi: TIntFile;
  fr: file of TRec;
  fu: file;
  r: TRec;
  i, n, sum, v: Integer;
  bufOut, bufIn: array[0..7] of Integer;
  got: Int64;
begin
  ok := 0; tot := 0;
  { TESTMGR_TMP FIRST: testmgr launches jobs through an env allowlist
    (PXX_ TESTMGR_ LC_ QEMU_ plus a fixed set), and TESTTMP is not in it -- so
    reading TESTTMP alone returns nothing under testmgr and the fallback lands
    on the shared /tmp path, which is exactly as collision-prone as the literal
    it was written to avoid. TESTTMP second is what `make test
    TESTTMP=$(mktemp -d)` exports; /tmp last keeps a bare run byte-identical. }
  tmpdir := GetEnvironmentVariable('TESTMGR_TMP');
  if tmpdir = '' then tmpdir := GetEnvironmentVariable('TESTTMP');
  if tmpdir = '' then tmpdir := '/tmp';
  pathI := tmpdir + '/test_typed_file_i.bin';
  pathR := tmpdir + '/test_typed_file_r.bin';
  pathU := tmpdir + '/test_typed_file_u.bin';

  Chk('sizeof TRec', SizeOf(TRec), 24);

  { ---- file of Integer, through a named alias and a var parameter ---- }
  Assign(fi, pathI);
  FillInts(fi, 5);
  Chk('size after 5 writes', FileSize(fi), 5);
  Chk('pos at end', FilePos(fi), 5);
  Seek(fi, 2);
  Chk('pos after seek', FilePos(fi), 2);
  Read(fi, n);
  Chk('third value', n, 30);
  Chk('pos after read', FilePos(fi), 3);
  ChkB('eof mid-file', Eof(fi), False);
  Seek(fi, 5);
  ChkB('eof at end', Eof(fi), True);
  Close(fi);

  { Re-open and walk the whole file — the idiom the feature exists for. }
  Reset(fi);
  sum := 0;
  while not Eof(fi) do
  begin
    Read(fi, n);
    sum := sum + n;
  end;
  Chk('sum of all', sum, 150);
  Close(fi);

  { Truncate is in RECORDS too: the cursor is a record index. }
  Reset(fi);
  Seek(fi, 3);
  Truncate(fi);
  Chk('size after truncate', FileSize(fi), 3);
  Close(fi);

  { ---- file of TRec ---- }
  Assign(fr, pathR);
  Rewrite(fr);
  for i := 0 to 2 do
  begin
    r.a := i + 1;
    r.b := (i + 1) * 1.5;
    r.c[0] := i; r.c[1] := i + 10; r.c[2] := i + 20; r.c[3] := i + 30;
    Write(fr, r);
  end;
  Chk('rec count', FileSize(fr), 3);
  Seek(fr, 1);
  Read(fr, r);
  Chk('rec[1].a', r.a, 2);
  Chk('rec[1].b*10', Round(r.b * 10), 30);
  Chk('rec[1].c[3]', r.c[3], 31);
  Chk('rec pos', FilePos(fr), 2);
  Close(fr);

  { Read-modify-write in place — Reset must open for writing, not read-only. }
  Reset(fr);
  Seek(fr, 0);
  Read(fr, r);
  r.a := 99;
  Seek(fr, 0);
  Write(fr, r);
  Seek(fr, 0);
  Read(fr, r);
  Chk('rewritten a', r.a, 99);
  Close(fr);

  { ---- untyped file: BlockWrite/BlockRead in blocks of one byte ---- }
  for i := 0 to 7 do bufOut[i] := i * 7;
  Assign(fu, pathU);
  Rewrite(fu, 1);
  BlockWrite(fu, bufOut, SizeOf(bufOut));
  Chk('untyped size', FileSize(fu), SizeOf(bufOut));
  Close(fu);

  Reset(fu, 1);
  for i := 0 to 7 do bufIn[i] := -1;
  BlockRead(fu, bufIn, SizeOf(bufIn), got);
  Chk('blockread got', got, SizeOf(bufIn));
  Chk('bufIn[0]', bufIn[0], 0);
  Chk('bufIn[7]', bufIn[7], 49);
  Close(fu);

  { ---- a LITERAL and a CONSTANT-FOLDED expression as the write argument ----
    Not decoration. The write side converts through a temp of the element type,
    and that temp used to be taken only when the argument's width or kind
    DIFFERED from the element's. A bare `42` for a `file of Integer` differs in
    neither, so it took no temp and reached IR lowering as an AN_INT_LIT with no
    address: `IR_UNSUPPORTED: frontend could not lower AST node (kind 1)`. The
    variable form and the expression form both worked throughout, which is why
    nothing else here caught it -- `i * 10` is Int64 and therefore always
    converted. These rows pin the one shape that matched exactly.
    Byte-compared against fpc 3.2.2: 12 bytes, identical. }
  Assign(fi, pathI);
  Rewrite(fi);
  Write(fi, 42);
  Write(fi, -7);
  Write(fi, 1000000);
  Close(fi);
  Reset(fi);
  Chk('literal size', FileSize(fi), 3);
  Read(fi, v);  Chk('literal 42', v, 42);
  Read(fi, v);  Chk('literal -7', v, -7);
  Read(fi, v);  Chk('literal 1e6', v, 1000000);
  Close(fi);

  writeln('total ok ', ok, ' / ', tot);
end.

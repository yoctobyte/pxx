{$define PXX_MANAGED_STRING}
program test_dynarray_copy_managed_elems;

{ Copy() over an array whose ELEMENTS are managed must RETAIN what it copied.
  AN_DYN_COPY moves the elements with a raw byte copy, so the fresh buffer holds
  the source's handles with no refcount adjustment — and the temp is
  element-aware released, which then frees strings the SOURCE still owns.

  The bug was latent for a long time and invisible on a plain run: the retain was
  accidentally supplied by IR_DYNUNIQUE's copy-on-write clone, which calls
  PXXDynArrayRetainImmediate on the block it clones. Removing the COW
  (bug-a-x86-64-dynarray-assignment-copies-instead-of-aliasing) took that side
  effect away. Even then a plain run PASSED, because freed bytes still held the
  old text until something reused them; `-dPXX_HEAP_DEBUG` fills them with $DD
  and the value became empty. That is the whole point of the tool
  (devdocs/dev/debugging-playbook.md).

  So: RUN THIS UNDER -dPXX_HEAP_DEBUG TOO. Without it, this file cannot fail for
  the reason it exists. The Makefile rule does both.

  Every value below was diffed against an FPC build of this same file. }

{ Counted rather than printed per check: the churn loop runs 200 iterations of
  every assertion, and 2212 lines of `1` makes a Makefile expectation nobody can
  read. One total that must equal the number of checks performed. }
var
  Checks, Fails: Integer;

procedure Check(ok: Boolean);
begin
  Inc(Checks);
  if not ok then Inc(Fails);
end;

type
  TS = array of AnsiString;
  TRec = record Name: AnsiString; N: Integer; end;
  TR = array of TRec;

procedure StringElems;
var a, b: TS;
begin
  SetLength(a, 3);
  a[0] := 'alpha'; a[1] := 'beta'; a[2] := 'gamma';
  b := Copy(a, 0, 3);
  Check(b[0] = 'alpha');
  Check(b[2] = 'gamma');

  { the write releases b[0]'s handle — which is the SAME handle as a[0] unless
    the copy retained it. This is the assertion the bug broke. }
  b[0] := 'CHANGED';
  Check(a[0] = 'alpha');
  Check(b[0] = 'CHANGED');
  Check(a[1] = 'beta');

  { the whole-array shorthand takes the same path }
  b := Copy(a);
  b[1] := 'OTHER';
  Check(a[1] = 'beta');
  Check(b[1] = 'OTHER');
end;

procedure RecordElems;
var a, b: TR;
begin
  SetLength(a, 2);
  a[0].Name := 'first'; a[0].N := 1;
  a[1].Name := 'second'; a[1].N := 2;
  b := Copy(a, 0, 2);
  Check(b[0].Name = 'first');
  Check(b[1].N = 2);
  b[0].Name := 'REPLACED';
  Check(a[0].Name = 'first');
  Check(b[0].Name = 'REPLACED');
end;

{ Scope exit is where a missing retain turns into a double free: the temp's
  element-aware release runs on every iteration. }
procedure Churn;
var i: Integer;
begin
  for i := 1 to 200 do
  begin
    StringElems;
    RecordElems;
  end;
end;

begin
  Checks := 0; Fails := 0;
  StringElems;
  RecordElems;
  Churn;
  writeln('checks ', Checks, ' fails ', Fails);
end.

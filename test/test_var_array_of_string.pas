program TestVarArrayOfString;
{ Regression for bug-var-array-of-ansistring-param-loses-writes: a var/out
  array-of-AnsiString parameter's element symbol stores its ELEMENT type
  (tyAnsiString) in .TypeKind, same field a genuinely-local scalar AnsiString
  var uses. A codegen guard (ir_codegen.inc, IR_LEA under InLValueWrite)
  matched on TypeKind=tyAnsiString alone, without excluding arrays, so a
  var/out array-of-AnsiString param wrongly got `lea` (address of its own
  local forwarded-pointer slot) instead of `mov` (dereference to reach the
  caller's real array) -- writes landed inside the callee's own frame and
  vanished on return; worse, the managed-string store's "release the old
  value" step decremented a refcount at a bogus computed address (memory
  corruption, not just data loss). Covers both fixed and open-array shapes,
  index > 0 (ruling out an idx=0 coincidental-collision-only fix), a scalar
  var AnsiString param (must stay correct, it's the sibling branch this
  bug's fix mirrors), and a const array-of-AnsiString param (read path,
  unaffected, must stay correct). }
type
  TArr = array[0..3] of AnsiString;

procedure FillFixed(var a: TArr; idx: Integer; const v: AnsiString);
begin
  a[idx] := v;
end;

procedure FillOpen(var a: array of AnsiString; idx: Integer; const v: AnsiString);
begin
  a[idx] := v;
end;

procedure FillScalar(var s: AnsiString; v: AnsiString);
begin
  s := v;
end;

function ReadConst(const a: TArr; idx: Integer): AnsiString;
begin
  Result := a[idx];
end;

var
  x: TArr;
  s: AnsiString;
  i: Integer;
  total: Integer;
begin
  x[0] := 'unset0'; x[1] := 'unset1'; x[2] := 'unset2'; x[3] := 'unset3';
  FillFixed(x, 0, 'hello0');
  FillFixed(x, 3, 'hello3');
  writeln(x[0], ' ', x[1], ' ', x[2], ' ', x[3]);
  FillOpen(x, 1, 'open1');
  FillOpen(x, 2, 'open2');
  writeln(x[0], ' ', x[1], ' ', x[2], ' ', x[3]);
  s := 'before';
  FillScalar(s, 'after');
  writeln(s);
  writeln(ReadConst(x, 0), ' ', ReadConst(x, 3));

  { repeated writeback through the same slot: proves the fix's ARC handling
    (release-old/retain-new) is correct at the real caller address, not just
    that a single write happens to land right }
  total := 0;
  for i := 0 to 4999 do
  begin
    FillFixed(x, 0, 'padding-value-to-exercise-realloc-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx');
    Inc(total, Length(x[0]));
  end;
  writeln('loop total=', total, ' final=', x[0]);
end.

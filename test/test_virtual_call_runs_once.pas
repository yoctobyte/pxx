{ A VIRTUAL CALL WHOSE RESULT IS USED MUST RUN ONCE.

  This counts CALLS, not allocations, and that is the point of it. The defect it
  guards against was found as an allocation census -- xtensa reported 7707
  allocs where every other backend reported 3799 for the same source, filed as
  "allocates twice per virtual call returning a string and leaks one". The
  allocation count was the SHADOW. What actually happened is that the whole
  virtual call was emitted twice, so the callee RAN twice, and everything it did
  happened twice: a counter, a write, a file append, a device poke. The leak was
  just the half of the doubled work nothing owned.

  Cause: the xtensa statement walker's `case` ends in `else IREmitNodeXtensa(i)`,
  and IR_VIRTUAL_CALL had no arm of its own -- so it was emitted at statement
  level by the catch-all AND again by the parent consuming its value. riscv32
  and arm32 both carried the guarded arm already.

  A CENSUS COULD NOT HAVE CAUGHT THIS AT FULL STRENGTH: it only sees the doubling
  when the callee happens to allocate. The Integer row below doubled just as
  hard and moved no counter a census reads.

  THE LAST ROW IS A POSITIVE CONTROL AND IS NOT DECORATION. The obvious wrong
  fix is to add IR_VIRTUAL_CALL to the walker's do-nothing list instead of
  guarding it with IRStmtRoot. That silences the double emission and passes
  every other row here -- and it deletes virtual PROCEDURE calls entirely,
  because a discarded result has only the statement-level emission to begin
  with. `calls` would read 0. Any change that breaks the guard breaks this row
  in the opposite direction from the others. }
program test_virtual_call_runs_once;

var
  calls: Integer;

type
  TBase = class
    function FStr(n: Integer): AnsiString; virtual;
    function FInt(n: Integer): Integer; virtual;
    procedure PVoid(n: Integer); virtual;
  end;
  TDerived = class(TBase)
    function FInt(n: Integer): Integer; override;
  end;

function TBase.FStr(n: Integer): AnsiString;
begin Inc(calls); FStr := Chr(65 + (n mod 26)); end;
function TBase.FInt(n: Integer): Integer;
begin Inc(calls); FInt := n; end;
procedure TBase.PVoid(n: Integer);
begin Inc(calls); end;
function TDerived.FInt(n: Integer): Integer;
begin Inc(calls); FInt := n * 2; end;

const N = 100;

procedure Check(const what: AnsiString; want: Integer);
begin
  if calls <> want then
  begin
    WriteLn('FAIL: ', what, ' ran ', calls, ' times, want ', want);
    Halt(1);
  end;
  calls := 0;
end;

var
  o: TBase;
  d: TDerived;
  s: AnsiString;
  i, k: Integer;
begin
  o := TBase.Create;
  d := TDerived.Create;

  calls := 0;
  for i := 1 to N do s := o.FStr(i);
  Check('managed-string result assigned', N);

  for i := 1 to N do k := o.FInt(i);
  Check('integer result assigned', N);

  for i := 1 to N do k := Length(o.FStr(i));
  Check('string result consumed by Length', N);

  for i := 1 to N do k := o.FInt(i) + o.FInt(i);
  Check('two calls in one expression', 2 * N);

  for i := 1 to N do k := d.FInt(i);
  Check('overridden result assigned', N);

  { The control -- see the header. }
  for i := 1 to N do o.PVoid(i);
  Check('discarded result (procedure)', N);

  if Length(s) <> 1 then
  begin WriteLn('FAIL: last string result is ', Length(s), ' chars, want 1'); Halt(1); end;
  if k <> N * 2 then
  begin WriteLn('FAIL: last integer result is ', k, ', want ', N * 2); Halt(1); end;

  WriteLn('VIRTUAL CALL RUNS ONCE OK');
end.

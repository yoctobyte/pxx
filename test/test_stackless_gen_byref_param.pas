{ A BY-REF parameter of a `generator; stackless;` routine.

  The instance slot for a by-ref parameter persists the caller's ADDRESS — that
  is the arm AssignStacklessSlots, SLSaveLocals and SLRestoreLocals all take. The
  for-in caller stored the argument the way it stores every other one, which
  evaluates it as a VALUE, so the two ends disagreed about what the word means
  and the step function dereferenced the value.

  It hid because it does not fire for the by-ref shape people write most: a
  RECORD argument's bare ident already evaluates to its address, so `const r: TR`
  and `r: TR` were right by construction and only a SCALAR `var` was wrong.
  Both kinds are below for that reason.

  `writes_back` is the row that cannot be satisfied by a copy: a `var` parameter
  must alias the caller's variable, so an address-of-a-temporary fix would still
  yield 41 from inside the generator and leave mm at 40 outside. Reading alone
  cannot tell the two apart.
  bug-a-a-var-parameter-of-a-stackless-generator-stores-the-value-where-the-slot-expects-an-address }
program test_stackless_gen_byref_param;
uses slgen;

type TR = record a, b: Int64; end;

{ scalar var: the crashing shape. }
function GVarRead(var m: Int64): Integer; generator; stackless;
begin yield m; yield m + 1; end;

{ the same, mutating: the caller's variable must see it. }
function GVarWrite(var m: Int64): Integer; generator; stackless;
begin m := m + 1; yield m; end;

{ const record: right by construction before the fix, so this is the row that
  catches the fix breaking what already worked. }
function GConstRec(const r: TR): Integer; generator; stackless;
begin yield r.a; yield r.b; end;

{ value record: same ABI, and it must not be double-addressed either. }
function GValRec(r: TR): Integer; generator; stackless;
begin yield r.a; yield r.b; end;

var x: Integer; mm: Int64; v: TR;
begin
  mm := 40;
  for x in GVarRead(mm) do write(x, ' ');
  writeln;

  mm := 40;
  for x in GVarWrite(mm) do write(x, ' ');
  writeln(mm);

  v.a := 11; v.b := 22;
  for x in GConstRec(v) do write(x, ' ');
  writeln;
  for x in GValRec(v) do write(x, ' ');
  writeln;
end.

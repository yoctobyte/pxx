program test_managed_record_funcname_return;

{ Returning a managed record BY VALUE from a function. The callee builds a
  local record with an AnsiString field, then returns it. If the copy-out into
  the caller's hidden destination does not participate in ARC (no retain) while
  the local is released on scope exit, the returned string is freed under the
  caller -> use-after-free / refcount underflow. }

{$define PXX_MANAGED_STRING}

type
  TRec = record
    s: AnsiString;
    n: Integer;
  end;

procedure Check(ok: Boolean);
begin
  if ok then writeln(1) else writeln(0);
end;

{ Case A: return a fresh local record (local released on scope exit). }
function MakeLocal(v: AnsiString): TRec;
var r: TRec;
begin
  r.s := v;
  r.n := 7;
  MakeLocal := r;        { copy local -> Result, then local released at exit }
end;

{ Case B: return via Result directly (no separate local). }
function MakeResult(v: AnsiString): TRec;
begin
  Result.s := v;
  Result.n := 9;
end;

var
  a, b: TRec;
  i: Integer;
begin
  a := MakeLocal('alpha');
  Check(a.s = 'alpha');
  Check(a.n = 7);

  b := MakeResult('beta');
  Check(b.s = 'beta');
  Check(b.n = 9);

  { Hammer the heap to expose a freed/aliased string. If MakeLocal's copy-out
    did not retain, 'alpha' storage was freed and may be reused below. }
  for i := 1 to 50 do
    a := MakeLocal('alpha');
  Check(a.s = 'alpha');
end.

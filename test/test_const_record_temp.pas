{ Regression: a function-result (or any non-lvalue) record temporary may be
  passed to a `const` record parameter. The compiler materializes the temp into
  a hidden local and passes its address, like FPC. `var`/`out` record params
  still require a true lvalue (covered by other tests).
  Plain (unmanaged) record so this runs identically on every target; the
  managed (dynarray-field) variant lives in test_const_record_temp_managed.pas
  (x86-64 only — a separate pre-existing const managed-record-param crash on
  i386/aarch64 is tracked in bug-const-managed-record-param-byref-crash).
  Ticket: bug-const-byref-record-param-temp. }
program test_const_record_temp;

type
  TR = record
    x, y: Int64;
  end;

function MakeR(v: Int64): TR;
begin
  Result.x := v;
  Result.y := v * 10;
end;

function AddR(const a, b: TR): TR;
begin
  Result.x := a.x + b.x;
  Result.y := a.y + b.y;
end;

function SumR(const r: TR): Int64;
begin
  SumR := r.x + r.y;
end;

var
  p: TR;
begin
  { direct temp arg to const param }
  Writeln(SumR(MakeR(7)));                           { 7 + 70 = 77 }
  { both args are temps }
  p := AddR(MakeR(40), MakeR(2));
  Writeln(p.x);                                      { 42 }
  Writeln(p.y);                                      { 420 }
  { nested: temp result fed into another const-param call }
  p := AddR(AddR(MakeR(10), MakeR(20)), AddR(MakeR(5), MakeR(7)));
  Writeln(p.x);                                      { 42 }
  { mix of named var and temp }
  p := MakeR(100);
  p := AddR(p, MakeR(1));
  Writeln(p.x);                                      { 101 }
end.

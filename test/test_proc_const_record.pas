program test_proc_const_record;
{ bug-proc-typed-call-const-record-arg (scalar form): an indirect call through a
  proc-typed variable whose signature has a `const record` parameter must pass the
  arg the same way the callee receives it (by reference). The proc-TYPE parser now
  applies the same const-record->by-ref rule as a real routine, so signature and
  callee agree (was: segfault). }
type
  TRec = record a, b: Integer; end;
  TFn  = function(const r: TRec): Integer;
function Sum(const r: TRec): Integer;
begin
  Sum := r.a + r.b;
end;
var
  fn: TFn;
  r: TRec;
begin
  r.a := 30; r.b := 12;
  writeln(Sum(r));            { 42 - direct }
  fn := @Sum;
  writeln(fn(r));             { 42 - indirect scalar, const record }
end.

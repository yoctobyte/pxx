program test_atomic64;
{ 64-bit atomic intrinsics (__pxxatomic_xchg64/cas64/add64): full-width
  lock-prefixed rmw. The shared counter starts just below 2^32 so a 32-bit
  op would wrap and lose the high dword — the final value proves the ops are
  genuinely 64-bit. Compile with --threadsafe. }
uses palthread;

const
  NT = 4;
  NADD = 200000;
  BASE = 4294967000;   { 2^32 - 296 }

var
  counter: Int64;
  handles: array[0..NT-1] of TThreadHandle;

procedure Worker(arg: Pointer);
var
  i: Integer;
  ignore: Int64;
begin
  for i := 1 to NADD do
    ignore := __pxxatomic_add64(@counter, 1);
end;

var
  i: Integer;
  v, old: Int64;
begin
  { single-thread semantics first: old-value returns + full-width stores }
  v := 0;
  old := __pxxatomic_xchg64(@v, 5000000000);          { > 2^32 }
  if (old = 0) and (v = 5000000000) then writeln('xchg64 OK');
  old := __pxxatomic_cas64(@v, 5000000000, 6000000000);
  if (old = 5000000000) and (v = 6000000000) then writeln('cas64 hit OK');
  old := __pxxatomic_cas64(@v, 123, 777);
  if (old = 6000000000) and (v = 6000000000) then writeln('cas64 miss OK');
  old := __pxxatomic_add64(@v, 1000000000);
  if (old = 6000000000) and (v = 7000000000) then writeln('add64 OK');

  { contention: NT threads x NADD adds across the 2^32 boundary }
  counter := BASE;
  for i := 0 to NT-1 do
    PalThreadCreate(handles[i], @Worker, nil, 0);
  for i := 0 to NT-1 do
    PalThreadJoin(handles[i]);
  writeln('counter=', counter, ' expected=', BASE + Int64(NT) * NADD);
  if counter = BASE + Int64(NT) * NADD then writeln('ATOMIC64 OK');
end.

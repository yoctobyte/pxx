program test_atomic_counter;
{ M2: atomic intrinsics under real contention (x86-64). NT threads each do K
  __pxxatomic_add(@counter, 1); the final counter must be exactly NT*K — any
  non-atomic read-modify-write would lose updates. Also checks __pxxatomic_cas /
  __pxxatomic_xchg return the correct old value. Builds on the M1 thread PAL. }
uses palthread;

const
  NT = 4;
  K  = 200000;

var
  counter: Integer;     { hammered concurrently via atomic add }

procedure Worker(arg: Pointer);
var
  j: Integer;
  ignore: Int64;
begin
  for j := 1 to K do
    ignore := __pxxatomic_add(@counter, 1);
end;

var
  h: array[0..NT-1] of TThreadHandle;
  i: Integer;
  v, old: Integer;
begin
  { single-threaded sanity on the three ops first }
  counter := 10;
  old := __pxxatomic_xchg(@counter, 99);          { old=10, counter:=99 }
  writeln('xchg old=', old, ' now=', counter);
  old := __pxxatomic_cas(@counter, 99, 7);        { matches -> counter:=7, old=99 }
  writeln('cas hit old=', old, ' now=', counter);
  old := __pxxatomic_cas(@counter, 99, 123);      { no match -> unchanged, old=7 }
  writeln('cas miss old=', old, ' now=', counter);
  old := __pxxatomic_add(@counter, 5);            { old=7, counter:=12 }
  writeln('add old=', old, ' now=', counter);

  { contended counter }
  counter := 0;
  for i := 0 to NT - 1 do
    if PalThreadCreate(h[i], @Worker, nil, 0) <> 0 then
    begin writeln('spawn FAIL ', i); Halt(1); end;
  for i := 0 to NT - 1 do
    PalThreadJoin(h[i]);

  v := counter;
  writeln('counter=', v, ' expected=', NT * K);
  if v = NT * K then writeln('ATOMIC OK') else writeln('ATOMIC FAIL');
end.

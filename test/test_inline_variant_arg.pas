{ A Variant argument to an INLINED leaf: at -O2 the inliner bound it by raw
  lowering, which is the Variant's TAG, so f(v) printed 1 for v = 205 and a
  second-position Variant printed an address. -O0 and a non-inlined call were
  right. The NilPy twin (promotable ints too) is
  test/test_nilpy_inline_boxed_args.npy. }
program test_inline_variant_arg;
function f(a: Int64): Int64; begin f := a; end;
function g(a, b: Integer): Integer; begin g := a - b; end;
var v: Variant; i: Int64;
begin
  v := 205; i := 7;
  writeln(f(v), ' ', g(1000, v), ' ', g(v, 5), ' ', f(i * 3));
end.

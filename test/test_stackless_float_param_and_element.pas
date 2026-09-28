{ A FLOAT parameter, local and element of a stackless generator.

  SlSet/SlGet move an Int64 and convert NUMERICALLY at each end, so a Double
  parameter of 2.5 arrived as its bit pattern read as an integer
  (4612811918334230528.0), a Single local lost its fraction across a yield, and
  a yielded Double came out as its bit pattern (x86-64, aarch64) or as garbage
  (i386, arm32, riscv32). Floats now ride their slots bitwise.
  bug-a-a-float-parameter-of-a-stackless-generator-arrives-as-its-bit-pattern }
program test_stackless_float_param_and_element;
uses slgen;

function G(d: Double; s: AnsiString; f: Single; n: Integer): Double; generator; stackless;
var acc: Double;
begin
  acc := d / 4;
  WriteLn('in ', d:0:2, ' ', s, ' ', f:0:3, ' ', n);
  yield d;
  yield acc;
  yield f + n;
end;

function H(k: Integer): Single; generator; stackless;
var x: Single; i: Integer;
begin
  x := 0.5;
  for i := 1 to k do begin yield x; x := x * 3; end;
end;

var v: Double; w: Single; t: AnsiString; c: Integer;
begin
  t := 'abc';
  for v in G(2.5, t, 0.125, 3) do WriteLn(v:0:3);
  { integer arguments convert into the float parameters, as on a plain call }
  for v in G(7, 'lit', 1, 2) do WriteLn(v:0:3);
  for v in H(3) do WriteLn(v:0:3);
  c := 0;
  for w in H(2) do begin c := c + 1; WriteLn(w:0:2); end;
  WriteLn(c);
end.

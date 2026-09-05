{ A `generator; stackless;` routine with a VARIANT PARAMETER.

  A Variant value parameter is passed BY REFERENCE — its frame slot holds a
  POINTER to the 16 bytes, not the bytes — and nothing marks it IsRef, so the
  slot pass used to treat it as a 16-byte value: it blob-copied SIXTEEN bytes
  into a slot that is EIGHT and ran over the neighbouring frame slot. Which
  neighbour decided the symptom, so BOTH shapes below are load-bearing:

    Variant FIRST  -> the neighbour is the hidden `self`, zeroed, and the step
                      function then dereferenced its own null instance pointer.
                      SIGSEGV, which read from outside as "the generator yielded
                      nothing" and was filed that way.
    Variant SECOND -> the neighbour is the previous parameter, silently clobbered
                      to 0. `first_param_survives` is the row that catches this;
                      a body yielding a CONSTANT passes either way, which is why
                      the original four-row repro set missed it entirely.

  Every row here yields a value that differs from both 0 and the arithmetic
  default, so a slot that was never written cannot be mistaken for a correct one.
  bug-a-a-stackless-generator-with-a-variant-parameter-yields-nothing-on-native-and-a-wrong-value-on-wasm32 }
program test_stackless_gen_variant_param;
uses slgen;

{ Variant FIRST and read: the crash shape. }
function GVarOnly(c: Variant): Integer; generator; stackless;
begin yield Integer(c); end;

{ Read across TWO yields: the value must survive suspension, not merely arrive. }
function GAcrossYield(c: Variant): Integer; generator; stackless;
begin yield Integer(c); yield Integer(c) + 1; end;

{ Variant SECOND, and the body READS the first parameter — the row that fails
  by a wrong value rather than a crash. }
function GFirstSurvives(a: Integer; c: Variant): Integer; generator; stackless;
begin yield a; yield Integer(c); end;

{ Two variants: each must land in its own slot. }
function GTwoVariants(a: Variant; b: Variant): Integer; generator; stackless;
begin yield Integer(a); yield Integer(b); end;

{ A MANAGED payload, read after a yield: the bytes are copied bitwise and the
  value must still be a live string on resumption. }
function GManaged(c: Variant): Integer; generator; stackless;
begin yield Length(AnsiString(c)); yield Length(AnsiString(c)) * 2; end;

var x: Integer;
begin
  for x in GVarOnly(7) do write(x, ' ');
  writeln;
  for x in GAcrossYield(7) do write(x, ' ');
  writeln;
  for x in GFirstSurvives(9, 7) do write(x, ' ');
  writeln;
  for x in GTwoVariants(4, 9) do write(x, ' ');
  writeln;
  for x in GManaged('hello') do write(x, ' ');
  writeln;
end.

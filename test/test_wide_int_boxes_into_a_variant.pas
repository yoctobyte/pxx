program test_wide_int_boxes_into_a_variant;
{ An Int64 assigned to a Variant keeps all sixty-four of its bits, in every
  shape that does the assigning.

  The two 32-bit backends moved only FOUR bytes into the 8-byte payload and
  then filled the high word from the TAG -- sign-extended for VT_INT, zero for
  everything else. An Int64 maps to VT_INT64, so it was zero-filled from a
  value that had already been truncated: `v := l` with l = 5000000000 stored
  705032704 on i386 and arm32, and with l = -12 stored 4294967284. Nothing
  failed; every operator downstream simply answered correctly for the wrong
  operand, and only a value that did not fit 32 bits made it visible.

  tyNativeInt rode the same defect from the other side: it maps to VT_INT64
  too, so a negative NativeInt was zero-filled into its unsigned reading even
  though it always fitted.

  The high word is now chosen from the payload's TYPE -- 64-bit payloads carry
  their own, signed narrow ones sign-extend, unsigned narrow ones zero-fill --
  and the boxing path pushes the whole pair.
  bug-a-an-int64-assigned-to-a-variant-truncates-to-32-bits-on-i386-and-arm32

  Every row is checked against a static Int64 rather than a hard-coded
  constant, and the rows are all shapes rather than all values, because the
  defect was in one emitter reached from several places: a plain assignment, a
  function result, a var parameter, a record field, an array element, a value
  parameter. Measured identical on x86-64, i386, arm32 and aarch64, and against
  fpc 3.2.2 -Mobjfpc -O1. riscv32 is absent on purpose: it refuses `var_store`
  in IR codegen and has no Variant support at all. }
uses variants;
type
  TRec = record v: Variant; end;
var
  fails: Integer;

procedure ChkI(const what: AnsiString; got, want: Int64);
begin
  if got <> want then
  begin
    writeln('FAIL ', what, ': got ', got, ' want ', want);
    fails := fails + 1;
  end;
end;

function WideResult: Int64;
begin
  WideResult := 5000000000;
end;

procedure StoreThroughVar(var d: Variant; l: Int64);
begin
  d := l;
end;

function RoundTripParam(d: Variant): Int64;
{ Through a LOCAL, not `RoundTripParam := d` directly. Assigning a Variant to
  the function result under the FUNCTION-NAME spelling skips the Variant
  conversion entirely and stores the slot ADDRESS -- on every target, x86-64
  included, while the `Result :=` spelling of the same line converts correctly.
  That is a separate defect, filed as
  bug-p-a-variant-assigned-to-the-result-by-function-name-is-not-converted;
  routing around it here keeps this test about the boxing it is named for. }
var t: Int64;
begin
  t := d;
  RoundTripParam := t;
end;

var
  a: Variant;
  r: TRec;
  arr: array[0..1] of Variant;
  l, want: Int64;
  n: NativeInt;
  c: Cardinal;
begin
  fails := 0;

  { the plain assignment, positive and negative, above and below 2^32 }
  want := 5000000000;
  l := want;      a := l;  ChkI('assign wide', a, want);
  l := -want;     a := l;  ChkI('assign wide neg', a, -want);
  l := -12;       a := l;  ChkI('assign small neg', a, -12);
  l := 5000000000; a := 5000000000; ChkI('assign literal', a, l);

  { tyNativeInt: always fits, but was zero-filled because it tags VT_INT64 }
  n := -12;       a := n;  ChkI('nativeint neg', a, -12);

  { an unsigned narrow payload must still zero-fill, not sign-extend }
  c := 3000000000; a := c; ChkI('cardinal high bit', a, 3000000000);

  { the other shapes that reach the same emitter }
  a := WideResult;         ChkI('function result', a, want);
  l := -want;
  StoreThroughVar(a, l);   ChkI('var parameter', a, -want);
  r.v := WideResult;       ChkI('record field', r.v, want);
  arr[0] := WideResult;
  arr[1] := 1;             ChkI('array element', arr[0], want);
  l := want;
  ChkI('value parameter', RoundTripParam(l), want);

  { and back out again, plus arithmetic and comparison on the boxed value }
  a := WideResult;
  l := a;                  ChkI('round trip', l, want);
  a := WideResult;
  a := a + 1;              ChkI('arithmetic', a, want + 1);
  a := WideResult;
  if not (a > 4999999999) then
  begin
    writeln('FAIL comparison: boxed wide value did not compare above 4999999999');
    fails := fails + 1;
  end;

  if fails = 0 then writeln('ALL OK') else writeln(fails, ' FAILURES');
end.

{ SPDX-License-Identifier: MPL-2.0 }
{ Phase 2 slice oracle. One source, two roles:
    - built natively (no define) it PRINTS the answers;
    - built with -dWASM_NOMAIN it has an empty main, so the wasm backend only
      has to handle the function bodies, not writeln — which is Phase 6.
  The harness calls the exported functions under node and compares.

  Every function here exists to make one Phase 2 claim FALSIFIABLE, so nothing
  in it is decoration:

    AddMul, Chain    32-bit arithmetic and a local that survives a statement.
    Wide             Int64 arithmetic as SINGLE wasm instructions — the design's
                     headline claim, and the thing no other 32-bit target in
                     this compiler can do (phase2-shadow-stack.md).
    Mix, Narrow      the width conversions the IR does not insert. Mix needs
                     i64.extend_i32_s, Narrow needs i32.wrap_i64; a register
                     backend needs neither, because a sub-register IS the
                     conversion.
                     Narrow is deliberately called with values that FIT in an
                     Integer. Out of range it would diverge for a reason that
                     is not this backend: assigning an Int64 to a function
                     RESULT does not narrow on x86-64 (it does for a variable,
                     a var parameter, and through a cast), so native prints
                     4294967299 where FPC and this backend both give 3 —
                     bug-a-function-result-assignment-does-not-narrow. The
                     instruction is still covered: without i32.wrap_i64 the
                     module does not validate at all.
    Pack             sub-word frame slots. symtab packs a frame by TypeSize
                     with no padding, so `b` here is ONE byte with `s`
                     immediately next to it: a 4-byte store into `b` writes
                     over `s`, and the wrong answer is the only symptom. The
                     constants are chosen so that any such overlap changes the
                     total.
    Cmp              comparisons, which produce i32 from operands of any width. }
program Phase2Slice;

function AddMul(a, b: Integer): Integer;
begin
  AddMul := a * b + 7;
end;

function Chain(x: Integer): Integer;
var t: Integer;
begin
  t := x + 1;
  t := t * t;
  Chain := t - x;
end;

function Wide(a, b: Int64): Int64;
var t: Int64;
begin
  t := a * b;
  Wide := t + a - b;
end;

function Mix(a: Integer; b: Int64): Int64;
begin
  Mix := a + b;
end;

function Narrow(a: Int64): Integer;
begin
  Narrow := a;
end;

function Pack(x: Integer): Integer;
var
  b: Byte;
  s: SmallInt;
  w: Word;
  c: ShortInt;
begin
  b := 200;
  s := -300;
  w := 60000;
  c := -100;
  Pack := b + s + w + c + x;
end;

{ Comparisons return Boolean and are NOT wrapped in Ord here: Ord on a Boolean
  lowers to an IR_CALL in this compiler (so does the Integer(b) cast), which is
  Phase 4. The harness converts on both sides instead, so what is compared is
  the comparison. }
function LtI(a, b: Integer): Boolean;
begin LtI := a < b; end;

function EqI(a, b: Integer): Boolean;
begin EqI := a = b; end;

function GeI(a, b: Integer): Boolean;
begin GeI := a >= b; end;

{ The signedness cases. These are the ones that DISCRIMINATE: wasm splits every
  ordering comparison into lt_s and lt_u, and 4294967295 < 1 is false unsigned
  and true signed, so picking the wrong instruction is a wrong answer here
  rather than a validation failure. }
function LtU(a, b: LongWord): Boolean;
begin LtU := a < b; end;

function LtW(a, b: Int64): Boolean;
begin LtW := a < b; end;

function EqW(a, b: Int64): Boolean;
begin EqW := a = b; end;

function Negate(x: Integer): Integer;
begin Negate := -x; end;

function NegateW(x: Int64): Int64;
begin NegateW := -x; end;

function BitNot(x: Integer): Integer;
begin BitNot := not x; end;

function LogNot(b: Boolean): Boolean;
begin LogNot := not b; end;

{ The shift operands are deliberately NON-NEGATIVE. Pascal's `shr` is a logical
  shift at the operand's own width, and pxx evaluates it at 64 bits whatever
  the operand type — `(-8) shr 1` on an Integer gives 9223372036854775804 where
  FPC gives 2147483644 — so a negative operand would make this diff red for a
  reason that is not this backend
  (bug-a-shr-on-a-32-bit-operand-is-evaluated-at-64-bits). Above zero the two
  widths agree and the instruction is still covered. }
function Bits(a, b: Integer): Integer;
begin
  Bits := (a and b) + (a or b) + (a xor b) + (a shl 2) + (a shr 1);
end;

function BitsW(a, b: Int64): Int64;
begin
  BitsW := (a and b) + (a or b) + (a xor b) + (a shl 2) + (a shr 1);
end;

{$ifndef WASM_NOMAIN}
begin
  writeln(AddMul(3, 4));
  writeln(AddMul(-2, 5));
  writeln(Chain(6));
  writeln(Chain(0));
  writeln(Wide(3000000000, 4));
  writeln(Wide(-5, 7));
  writeln(Mix(-7, 10000000000));
  writeln(Narrow(2147483647));
  writeln(Narrow(-1));
  writeln(Pack(0));
  writeln(Pack(1000));
  writeln(Ord(LtI(1, 2)));
  writeln(Ord(LtI(2, 2)));
  writeln(Ord(EqI(2, 2)));
  writeln(Ord(GeI(3, 2)));
  writeln(Ord(GeI(1, 2)));
  writeln(Ord(LtU(4294967295, 1)));
  writeln(Ord(LtU(1, 4294967295)));
  writeln(Ord(LtW(-10000000000, 1)));
  writeln(Ord(EqW(10000000000, 10000000000)));
  writeln(Negate(-2147483647));
  writeln(NegateW(-10000000000));
  writeln(BitNot(0));
  writeln(BitNot(-13));
  writeln(Ord(LogNot(False)));
  writeln(Ord(LogNot(True)));
  writeln(Bits(120, 5));
  writeln(BitsW(8000000000, 5));
end.
{$else}
begin
end.
{$endif}

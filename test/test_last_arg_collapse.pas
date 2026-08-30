program LastArgCollapse;
{ feature-opt-o3-w1-operand-folds-are-x86-64-only-aarch64-has-four-of-fifteen:
  the last-argument push/pop collapse, ported to aarch64.

  Arguments are evaluated into x0 and each pushed to a 16-byte temp; the pops
  then run in reverse into x0..x7. The LAST argument is pushed last and popped
  first with nothing in between, so the round trip is ceremony over a value
  already in x0. It becomes `mov x(n-1), x0` -- and for a ONE-argument call not
  even that, because the destination register IS x0.

  What can go wrong is an argument arriving in the WRONG REGISTER, which is a
  plausible number and never a crash. So every argument list here is a BAND --
  consecutive values -- combined with distinct weights, so ANY permutation of
  the arguments gives a different total. Far-apart values would let a swap that
  happens to cancel go unseen; consecutive ones cannot cancel.

  The rows, each for a distinct thing that can break:
    one    1 argument   -- the case where even the mov disappears
    two    2 arguments  -- the smallest case that has a mov at all
    eight  8 arguments  -- the boundary: still register-passed
    nine   9 arguments  -- OVER the boundary; the collapse must NOT fire, because
                          that path rebuilds an outgoing stack block from the
                          temp slots by offset and needs every slot to exist
    nest   the last argument is itself a CALL -- the inner collapse runs while
                          the outer one is mid-flight
    virt   a virtual call -- Self is argument 0 and is popped LAST, so a
                          collapse that disturbed x0 would break the VMT load
    indir  a call through a procedure variable -- the callee is pushed deepest,
                          so removing a matched pair at the top must leave it put

  Run at -O0 and -O3 on both targets: the collapse is -O3-gated and
  aarch64-only, so -O0 and x86-64 are independent controls on the same numbers.
  Values verified against FPC 3.2.2. }

type
  TBase = class
    function Score(p, q, r: Int64): Int64; virtual;
  end;
  TDerived = class(TBase)
    function Score(p, q, r: Int64): Int64; override;
  end;
  TFn2 = function(p, q: Int64): Int64;

var
  gAcc: Int64;
  gObj: TBase;
  gFn: TFn2;

function TBase.Score(p, q, r: Int64): Int64;
begin
  Score := p * 100 + q * 10 + r;
end;

function TDerived.Score(p, q, r: Int64): Int64;
begin
  Score := p * 1000 + q * 100 + r * 10;
end;

function One(a: Int64): Int64;
begin
  One := a * 7;
end;

function Two(a, b: Int64): Int64;
begin
  Two := a * 10 + b;
end;

function Eight(a, b, c, d, e, f, g, h: Int64): Int64;
begin
  { distinct weights: any permutation of a band changes the total }
  Eight := a*1 + b*2 + c*4 + d*8 + e*16 + f*32 + g*64 + h*128;
end;

function Nine(a, b, c, d, e, f, g, h, i: Int64): Int64;
begin
  Nine := a*1 + b*2 + c*4 + d*8 + e*16 + f*32 + g*64 + h*128 + i*256;
end;

function Inner(v: Int64): Int64;
begin
  Inner := v + 1;
end;

function Run(iters: LongInt): Int64;
var
  k: LongInt;
  a, b, c, d, e, f, g, h, i: Int64;   { a BAND: 10..18, consecutive }
  acc: Int64;
begin
  acc := 0;
  a := 10; b := 11; c := 12; d := 13; e := 14;
  f := 15; g := 16; h := 17; i := 18;
  for k := 1 to iters do
  begin
    acc := acc + One(a);
    acc := acc + Two(a, b);
    acc := acc + Eight(a, b, c, d, e, f, g, h);
    acc := acc + Nine(a, b, c, d, e, f, g, h, i);
    { the last argument is itself a call }
    acc := acc + Two(a, Inner(b));
    { virtual dispatch: Self is argument 0 and is restored last }
    acc := acc + gObj.Score(a, b, c);
    { indirect: the callee value is pushed deepest of all }
    acc := acc + gFn(a, b);
  end;
  Run := acc;
end;

begin
  gObj := TDerived.Create;
  gFn := @Two;
  gAcc := Run(3);
  WriteLn('acc=', gAcc);
  gAcc := Run(1);
  WriteLn('one=', gAcc);
  WriteLn('done');
end.

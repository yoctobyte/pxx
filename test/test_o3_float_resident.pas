{ -O3 float loop residency (xmm8..xmm13): every shape in which a tyDouble local
  or param can be register-resident, arranged so that each one's value reaches
  the output.

  Written for the item-3-for-floats question: the dual-write keeps the frame
  slot authoritative, and the proposed change stops writing it. That is safe
  only if nothing reads the slot. Grep says the sole non-residency-aware reader
  is FloatResidencyRefreshAll at the IR_EXC_ENTER landing pad -- but grep over
  10k lines is an audit with no completion criterion, so the real instrument is
  PXXDBG=a.poisonslot, and this is the program it runs on.

  Every case must therefore be POISON-VISIBLE: if the slot is read, the value
  must reach stdout. Cases that merely compute and discard would report clean
  regardless and are worse than useless -- they dilute the result. Verify with
  PXXDBG=a.poisonslot,a.poisonctl, which forces the reader: every line below
  must change under the control, or that line is not testing anything.

  Run at -O0/-O1/-O2/-O3: all four must agree. }
program test_o3_float_resident;
uses SysUtils;

type
  TDblFn = function(x: Double): Double;

var
  gAcc: Double;

function Times2(x: Double): Double;
begin
  Times2 := x * 2.0;
end;

{ Plain loop-carried double locals -- the mandelbrot shape. }
procedure Recurrence;
var i: LongInt; zr, zi, zr2, zi2, t, acc: Double;
begin
  zr := 0.0; zi := 0.0; acc := 0.0;
  for i := 1 to 400 do
  begin
    zr2 := zr * zr;
    zi2 := zi * zi;
    t   := zr2 - zi2 + 0.31;
    zi  := 2.0 * zr * zi + 0.02;
    zr  := t;
    if zr2 + zi2 > 100.0 then
    begin
      zr := 0.0; zi := 0.0;
    end;
    { Accumulate, so the printed value depends on EVERY iteration rather than
      on the last one. Without this the loop's escape-reset leaves zr=zi=0 and
      the line reads 0.000000 whatever happened in between -- a weak observable
      that the poison control happened to move anyway, which is luck, not a
      test. Sum the state instead. }
    acc := acc + zr + zi;
  end;
  Writeln('REC zr=', zr:0:6, ' zi=', zi:0:6, ' acc=', acc:0:6);
end;

{ A double VALUE param, written in the loop. }
procedure ValueParam(p: Double);
var i: LongInt; q: Double;
begin
  q := 1.0;
  for i := 1 to 300 do
  begin
    p := p * 1.0009;
    q := q + p * 0.0001;
  end;
  Writeln('VAL p=', p:0:6, ' q=', q:0:6);
end;

{ Residents live across an INTERNAL call, which the callee-saved discipline
  covers via the prologue/epilogue save-iff-used pair. }
procedure AcrossInternal;
var i: LongInt; a, b: Double;
begin
  a := 1.0; b := 0.0;
  for i := 1 to 200 do
  begin
    a := a * 1.001;
    b := b + Times2(a) * 0.001;
  end;
  Writeln('INT a=', a:0:6, ' b=', b:0:6);
end;

{ Residents live across an INDIRECT call, where the target is unprovable and
  the xmm8..13 pool is saved/restored around the site (FloatPoolSave pair,
  which uses the separate FxSaveBase area -- NOT the variable's own slot). }
procedure AcrossIndirect;
var i: LongInt; a, b: Double; f: TDblFn;
begin
  f := @Times2; a := 1.0; b := 0.0;
  for i := 1 to 200 do
  begin
    a := a * 1.001;
    b := b + f(a) * 0.001;
  end;
  Writeln('IND a=', a:0:6, ' b=', b:0:6);
end;

{ Residents live across an RTL math call. }
procedure AcrossMath;
var i: LongInt; a, b: Double;
begin
  a := 1.0; b := 0.0;
  for i := 1 to 200 do
  begin
    a := a + 0.01;
    b := b + Sqrt(a);
  end;
  Writeln('MTH a=', a:0:6, ' b=', b:0:6);
end;

{ A double resident in a body that HAS an exception frame. The item-3 gate
  refuses these (RcProcHasExc), so the poison must NOT fire here -- and the
  landing pad's refresh from the frame slot is exactly why. }
procedure WithExcFrame;
var i: LongInt; a: Double;
begin
  a := 1.0;
  for i := 1 to 200 do
  begin
    try
      a := a * 1.002;
      if i = 150 then raise Exception.Create('m');
    except
      on E: Exception do a := a + 1.0;
    end;
  end;
  Writeln('EXC a=', a:0:6);
end;

{ A double passed BY REFERENCE is excluded from residency (IsRef), and its
  slot is genuinely the storage rather than a cache. }
procedure ByRef(var r: Double);
var i: LongInt;
begin
  for i := 1 to 100 do r := r * 1.003;
end;

procedure RefCaller;
var d: Double;
begin
  d := 2.0;
  ByRef(d);
  Writeln('REF d=', d:0:6);
end;

{ Single NARROWS into its slot, so the slot is not a same-value cache of the
  register and residency excludes it -- `s` gets no xmm.

  `e` is the interesting one and it is NOT what its declaration suggests:
  `Extended` ALIASES Double in this dialect (feature-extended-alias-or-reject,
  pasparser_lval.inc's BuiltinScalarTypeKind), so `e` is tyDouble, IS resident,
  and IS poisoned. It is kept here under its misleading name deliberately: the
  residency pass restricts itself to tyDouble, and the only way to see that
  `Extended` is already inside that set is to declare one and look.

  That is how bug-p-sizeof-extended-disagrees-with-the-storage-extended-gets was
  found -- SizeOf(Extended) answers 10 for storage that is 8, because the
  DECLARATION path and the SizeOf path resolve the name in two different tables.
  If that bug is fixed, this case keeps working: it asserts the value, not the
  size. If `Extended` is ever made a real 80-bit type, `e` leaves the resident
  set and this case must be re-read rather than merely re-baselined. }
procedure NarrowTypes;
var i: LongInt; s: Single; e: Extended;
begin
  s := 1.0; e := 1.0;
  for i := 1 to 200 do
  begin
    s := s * 1.001;
    e := e * 1.001;
  end;
  Writeln('NAR s=', s:0:4, ' e=', e:0:6);
end;

{ A resident whose value reaches the output only through a GLOBAL, so the
  store path differs from the Writeln-of-a-local path above. }
procedure ViaGlobal;
var i: LongInt; a: Double;
begin
  a := 1.0;
  for i := 1 to 200 do a := a * 1.0015;
  gAcc := a;
  Writeln('GLB g=', gAcc:0:6);
end;

begin
  Recurrence;
  ValueParam(1.5);
  AcrossInternal;
  AcrossIndirect;
  AcrossMath;
  WithExcFrame;
  RefCaller;
  NarrowTypes;
  ViaGlobal;
end.

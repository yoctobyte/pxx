{ -O3 residency vs coroutine switches (pxx internal ABI §5b): a loop body
  holding float + int residents iterates a stackful generator every pass.
  CoSwitch saves only the GPR callee-saved set per context, so the xmm8-13 /
  d8-d13 pool is saved to the body's frame slots around IR_COSWITCH — the
  generator context (which runs its own float-heavy code) must not corrupt the
  consumer's residents. x86-64 stackful path (generators are x86-64-only).
  Output must be identical at every -O level (optdiff sweeps this). }
program test_residency_coswitch;
uses coroutine;

function Gen(n: Integer): Integer; generator;
var k: Integer;
    g: Double;
begin
  { float work INSIDE the generator context — clobbers d/xmm scratch and, if
    residency fired here, would claim pool registers of its own }
  g := 0.0;
  for k := 1 to n do
  begin
    g := g + k * 0.5;
    yield k + Round(g);
  end;
end;

procedure Run;
var x, s: Double;
    acc, chk: Int64;
    i, v: Integer;
begin
  x := 0.125; s := 0.0; acc := 7; chk := 0;
  for i := 1 to 500 do
  begin
    x := x + 0.0005;
    acc := acc + i;
    chk := chk xor acc;
    for v in Gen(3) do
      s := s + v * x * 0.001;
  end;
  writeln('s=', Round(s * 1000));
  writeln('x=', Round(x * 1000000));
  writeln('acc=', acc);
  writeln('chk=', chk);
end;

begin
  Run;
end.

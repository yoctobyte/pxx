{ -O3 residency ABI boundaries (pxx internal ABI §5b): a loop body holding int
  + float residents crosses every boundary the callee-saved discipline can't
  see through, and the residents must survive each one:

    - extern C call        (SysV/AAPCS callee: x86-64 wraps, aarch64 free)
    - indirect call        (plain procvar — target unprovable at the site)
    - raise across frames  (longjmp skips unwound epilogues; landing-pad
                            restore + refresh)
    - nested-routine write (lambda-lifted by-ref capture = addr-taken → the
                            captured var must be EXCLUDED from residency and
                            the outer read must see the nested write)
    - var-param aliasing   (helper writes through the by-ref param → same
                            addr-taken exclusion)

  Output must be identical at every -O level (optdiff sweeps this). }
program test_residency_boundaries;
uses sysutils;

function getenv(name: PAnsiChar): PAnsiChar; cdecl; external 'libc.so.6';

type
  TIntFn = function(n: Int64): Int64;

var glob: Double;

procedure Deep(n: Integer);
var a, b: Double;
    k: Integer;
begin
  a := 1.5; b := 2.5;
  for k := 1 to 8 do
  begin
    a := a + 0.25;
    b := b * 1.001;
  end;
  glob := a + b;
  if n = 0 then
    raise Exception.Create('boom');
end;

procedure Bump(var v: Double);
begin
  v := v + 1.0;
end;

function Twice(n: Int64): Int64;
begin
  Twice := n * 2;
end;

procedure Run;
var x, y, cap: Double;
    s, t, hits: Int64;
    i: Integer;
    fp: TIntFn;

  procedure Nested;
  begin
    { lambda-lifted by-ref capture: writes the enclosing local }
    cap := cap + 0.5;
  end;

begin
  x := 0.5; y := 0.25; cap := 0.0; s := 1; t := 3; hits := 0;
  fp := @Twice;
  for i := 1 to 2000 do
  begin
    x := x + 0.001;
    y := y * 1.0001 + x * 0.0001;
    s := s + i;
    t := t xor s;
    { extern C call: residents must survive the SysV/AAPCS boundary }
    if getenv('PXX_NO_SUCH_ENV_VAR') <> nil then hits := hits + 1000000;
    { indirect internal call through a procvar }
    t := t + fp(i and 7);
    { nested-routine write to a captured (addr-taken, non-resident) local }
    Nested;
    { var-param aliasing write }
    Bump(y);
    { raise from a callee with its own float residents, every 4th iteration }
    if (i and 3) = 0 then
      try
        Deep(0);
      except
        on E: Exception do Inc(hits);
      end;
  end;
  writeln('x=', Round(x * 1000000));
  writeln('y=', Round(y * 1000));
  writeln('cap=', Round(cap * 10));
  writeln('s=', s);
  writeln('t=', t);
  writeln('hits=', hits);
  writeln('glob=', Round(glob * 1000));
end;

begin
  Run;
end.

{ Hardware entropy intrinsics: __pxxCpuHasHwRandom / __pxxHwRandom64.

  lib/rtl/random.pas keeps per-arch instructions OUT of the .pas by design, so
  its tier-1 path needs these two entry points from the compiler's builtin unit.
  feature-a-rdrand-cpuid-compiler-builtins

  The assertions are written to hold on a CPU that HAS RDRAND and on one that
  does not, because that is the honest shape of a capability probe: what must be
  true is the RELATIONSHIP between the probe and the draw, never the presence of
  the instruction. On a machine without it every draw fails and the loop below
  reports 0 successes, which is a pass — the library's job is then to fall to
  tier 2.

  What a draw must never do is hand back a silent zero it calls entropy: RDRAND
  clears CF and leaves the destination ZERO when it fails, so `Result` is the
  only thing separating "here is randomness" from "here is nothing". }
program test_hw_random_intrinsics;
{$mode objfpc}{$H+}

var
  has: Boolean;
  v, prev: UInt64;
  i, ok, distinct: Integer;
  pass, fail: Integer;

procedure Chk(const what: AnsiString; cond: Boolean);
begin
  if cond then begin Inc(pass); writeln('ok   ', what); end
  else begin Inc(fail); writeln('FAIL ', what); end;
end;

begin
  pass := 0; fail := 0;
  has := __pxxCpuHasHwRandom;
  writeln('cpu has hardware rng: ', has);

  { The probe is cached; asking twice must not change the answer. }
  Chk('probe is stable', __pxxCpuHasHwRandom = has);

  ok := 0; distinct := 0; prev := 0;
  for i := 1 to 32 do
  begin
    v := $DEADBEEF;                  { poison, so a no-write is visible }
    if __pxxHwRandom64(v) then
    begin
      Inc(ok);
      if (i > 1) and (v <> prev) then Inc(distinct);
      prev := v;
    end;
  end;
  writeln('successful draws: ', ok, ' / 32');

  { The relationship, in both directions. }
  if has then
  begin
    Chk('a CPU with RDRAND produces at least one draw', ok > 0);
    { 32 draws all returning the same 64-bit value would mean the value is not
      being written at all — the failure a silent zero would look like. }
    Chk('draws differ from one another', (ok < 2) or (distinct > 0));
  end
  else
    Chk('no RDRAND means no successful draw', ok = 0);

  writeln('total ok ', pass, ' / ', pass + fail);
end.

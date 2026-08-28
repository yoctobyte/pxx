{ Tier 1 (hardware entropy) wiring in lib/rtl/random.pas.

  Deliberately asserts CONTRACTS, not values: RDRAND is present on this box but
  not on every box the suite runs on, so a test that demanded True would be
  testing the CPU rather than the library. Both branches of the availability
  probe print the same lines, so the expected output is machine-independent.

  The property with teeth is `seeded-reproducible`: tier 1 must not leak into
  the deterministic path. A seeded stream is by definition reproducible, so if
  wiring hardware entropy in changed it, the change would be invisible here
  (streams still look random) and catastrophic in use. }
program lib_random_hw_tier1;

uses random;

const
  DRAWS = 64;

var
  allok: Boolean;
  avail1, avail2: Boolean;
  v, prev: UInt64;
  i, successes, distinct: Integer;
  ok: Boolean;
  a, b: array[0..3] of UInt64;

begin
  allok := True;

  { The probe is CPUID-cached; two calls must agree. }
  avail1 := HWEntropyAvailable;
  avail2 := HWEntropyAvailable;
  if avail1 = avail2 then WriteLn('probe-stable=ok')
  else begin WriteLn('probe-stable=FAIL'); allok := False; end;

  { The contract, whichever way the probe answered. }
  if avail1 then
  begin
    successes := 0;
    distinct := 0;
    prev := 0;
    for i := 1 to DRAWS do
    begin
      v := 0;
      if HWEntropy64(v) then
      begin
        Inc(successes);
        if (successes > 1) and (v <> prev) then Inc(distinct);
        prev := v;
      end
      else
        { documented failure path: v must be left zeroed, never leaked }
        if v <> 0 then successes := -1000000;
    end;
    { A stuck source repeats; a working one essentially never does. Requiring
      only "most draws differ" keeps this from being a probability bet. }
    ok := (successes > DRAWS div 2) and (distinct > (successes - 1) div 2);
  end
  else
  begin
    v := 12345;
    ok := (not HWEntropy64(v)) and (v = 0);
  end;
  if ok then WriteLn('contract=ok')
  else begin WriteLn('contract=FAIL'); allok := False; end;

  { Tier 1 must not touch the seeded path, before or after it has been used. }
  XoshiroSeed(987654321);
  for i := 0 to 3 do a[i] := XoshiroNext;
  XoshiroRandomize;               { may consume hardware entropy }
  XoshiroSeed(987654321);
  for i := 0 to 3 do b[i] := XoshiroNext;
  ok := True;
  for i := 0 to 3 do if a[i] <> b[i] then ok := False;
  if ok then WriteLn('seeded-reproducible=ok')
  else begin WriteLn('seeded-reproducible=FAIL'); allok := False; end;

  { And the non-deterministic path must actually move. }
  XoshiroRandomize; v := XoshiroNext;
  XoshiroRandomize; prev := XoshiroNext;
  if v <> prev then WriteLn('randomize-varies=ok')
  else begin WriteLn('randomize-varies=FAIL'); allok := False; end;

  { The sentinel must be unreachable on failure, and the exit status must carry
    the verdict too. An earlier draft printed it unconditionally: the stuck-source
    negative control produced two FAIL lines, then 'HWTIER1 OK', then exit 0 --
    green to anything reading the last line or the status. }
  if allok then
    WriteLn('HWTIER1 OK')
  else
  begin
    WriteLn('HWTIER1 FAIL');
    Halt(1);
  end;
end.

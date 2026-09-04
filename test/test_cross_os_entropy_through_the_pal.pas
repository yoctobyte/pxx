program test_cross_os_entropy_through_the_pal;
{ OSEntropyBytes on every target, through PalRandomBytes.

  random.pas carried its own per-arch getrandom number table until 2026-09-04 --
  the fifth private copy of a table platform.pas already had. Its omission was
  spelled out in the source: "CPU_XTENSA (ESP32): no getrandom; use HW RNG
  register (tier 1)". That is TRUE OF ESP-IDF and false of xtensa LINUX, which
  is the posix backend's population -- the arch stood in for the platform. On
  wasm32 the same body was refused at codegen, so that target had no tier 2 at
  all, while wasi's random_get is a CSPRNG the spec requires to be
  cryptographic.

  TWO DRAWS, NOT ONE, AND THAT IS THE WHOLE DESIGN OF THIS TEST. The failure
  mode being guarded is a call that returns without filling the buffer, and the
  buffer is zero-initialised, so a single draw checked for "not all zero" is a
  guard whose expected value collides with the failure value. Two draws cannot:
  an unfilled buffer gives diff=0, and that is exactly what the pre-change
  xtensa build produced -- `okA=FALSE bytes differing: 0 zero bytes: 32`. A
  working CSPRNG differs in essentially every byte.

  The thresholds are loose on purpose (>= 24 of 32 differing, <= 6 zero bytes).
  This is a liveness-and-plumbing test, not a statistical one: two 32-byte draws
  cannot say anything about randomness QUALITY, and a tight bound here would be
  a flaky row pretending to be a strong one. What it can say is that the bytes
  came from somewhere that changes, which is the claim the syscall plumbing is
  responsible for.

  ESP is NOT expected to reach this path and is not a row here: tier 1 is the HW
  RNG register and runs first, so PalRandomBytes correctly answers
  PAL_ERR_UNSUPPORTED there. }
uses random;
var a, b: array[0..31] of Byte; okA, okB: Boolean; i, diff, zero: Integer;
begin
  for i := 0 to 31 do begin a[i] := 0; b[i] := 0; end;
  okA := OSEntropyBytes(@a[0], 32);
  okB := OSEntropyBytes(@b[0], 32);
  diff := 0; zero := 0;
  for i := 0 to 31 do
  begin
    if a[i] <> b[i] then Inc(diff);
    if a[i] = 0 then Inc(zero);
  end;
  if not (okA and okB) then WriteLn('FAIL: OSEntropyBytes returned False')
  else if diff < 24 then WriteLn('FAIL: only ', diff, ' of 32 bytes differ between two draws')
  else if zero > 6 then WriteLn('FAIL: ', zero, ' zero bytes in a 32-byte draw')
  else WriteLn('ENTROPY OK');
end.

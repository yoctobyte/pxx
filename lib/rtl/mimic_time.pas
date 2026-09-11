{ SPDX-License-Identifier: Zlib }
unit mimic_time;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `time` — the three clock entry points real code reaches for.

  `import time` RESOLVES here through the NilPy import resolver's `mimic_`
  fallback, so no file in the tree carries the stdlib's name and `--no-shims`
  can turn the substitution into an error. See
  devdocs/dev/python-compat-tiers.md.

  A PASCAL unit, for the same reason as [[mimic_shutil]]: these are syscalls.
  The PAL already has them at FULL RESOLUTION — PalClockGetTime hands back
  separate seconds and NANOseconds, and PalNanosleep takes the same pair — so
  this shim is a unit conversion and nothing more. There is no approximation
  here to apologise for.

  WHY NOT GetTickCount64, which was the obvious candidate: it is
  PalMonotonicMillis, so it is correctly monotonic and it is MILLISECONDS.
  lekkerzeilen calls `time.monotonic()` eighteen times and they are frame
  timing; at 60 fps a frame is 16.7 ms, so a 1 ms quantum is 6% of a frame and
  it lands in a dt that drives physics. CPython's `monotonic()` is
  nanosecond-sourced, and so is this. Resolution is part of this function's
  contract, not a quality-of-implementation detail.

  THE SUBSET: `monotonic`, `time`, `sleep`. Absent, and said out loud rather
  than approximated: `perf_counter` (would be a correct alias of monotonic here,
  but CPython documents it as the HIGHEST-resolution clock and promising that is
  a claim about the platform, not about this file), `strftime`/`localtime`/
  `gmtime`/`mktime` (calendar arithmetic and a timezone database — sysutils has
  the pieces and they want their own unit), `monotonic_ns`/`time_ns` (trivial
  once someone needs them — the nanoseconds are right here), and `process_time`.
  A missing name fails at the call site naming the member, which is found in one
  run.

  THE CLOCK IDS ARE LINUX NUMBERS AND THAT IS A REAL LIMIT. 0 is CLOCK_REALTIME
  (platform.pas's own comment for PalClockGetTime says so: "PalRealtime is one
  fixed case of (clockId 0)") and 1 is CLOCK_MONOTONIC. Those two happen to
  agree across Linux, the BSDs and Minix. They are NOT universal — a backend
  that numbers its clocks differently needs the ids moved behind the PAL, which
  is where they belong and where PalClockGetTime's own comment already points.
  Whoever ports this: the fix is a PAL constant, not a table here. }

interface

uses platform;

{ Seconds from an arbitrary origin, never going backwards. CPython leaves the
  origin undefined for exactly this reason, so CLOCK_MONOTONIC's boot-relative
  origin is conforming and callers may only subtract two readings. }
function monotonic: Double;

{ Seconds since the Unix epoch, as a float. Can jump, in both directions --
  it is the wall clock. }
function time: Double;

{ Suspend for `seconds`, which may be fractional. }
procedure sleep(seconds: Double);

implementation

const
  { See the unit header on why these live here and why that is a limit. }
  PY_CLOCK_REALTIME  = 0;
  PY_CLOCK_MONOTONIC = 1;
  NSEC_PER_SEC       = 1000000000;

{ Seconds and nanoseconds to one Double.

  The nanoseconds are divided BEFORE the addition, not after, so the sum is
  formed at the scale of the result. CLOCK_REALTIME's seconds are ~1.7e9 today,
  which needs 31 bits, and a Double's 53-bit mantissa leaves 22 bits for the
  fraction -- about 240 ns. That is the real floor on `time()` and it is
  CPython's floor too, for the same reason: a float carrying an absolute epoch
  has spent most of its precision on the integer part. `monotonic()` does not
  have this problem, its seconds being a small boot-relative number. }
function SecNsecToSeconds(sec, nsec: Int64): Double;
begin
  Result := Double(sec) + Double(nsec) / Double(NSEC_PER_SEC);
end;

function ReadClock(clockId: Integer): Double;
var sec, nsec: Int64;
begin
  sec := 0;
  nsec := 0;
  { A failing clock read returns 0.0 rather than raising. CPython would raise
    OSError, and matching that would be better -- but a clock this program
    cannot read is not a condition any caller here handles, and a frame loop
    that suddenly raises out of its timing call is a worse failure than one
    whose dt comes out zero. Revisit when something actually wants the error. }
  if PalClockGetTime(clockId, sec, nsec) <> 0 then
    Result := 0.0
  else
    Result := SecNsecToSeconds(sec, nsec);
end;

function monotonic: Double;
begin
  Result := ReadClock(PY_CLOCK_MONOTONIC);
end;

function time: Double;
begin
  Result := ReadClock(PY_CLOCK_REALTIME);
end;

procedure sleep(seconds: Double);
var sec, nsec: Int64;
    whole: Double;
begin
  { A DELIBERATE, MEASURED DIVERGENCE, and in the permitted direction.
    `sleep(0)` returns at once in CPython too. `sleep(-1)` does NOT: CPython
    raises `ValueError: sleep length must be non-negative` (verified, 3.14).
    This accepts it and returns.

    NilPy is UPWARD compatible with CPython -- accepting what CPython rejects is
    a feature, one direction (CLAUDE.md; nilpy-semantics-divergences.md). The
    reason to take that latitude here rather than matching: the idiom this
    protects is `sleep(deadline - now())`, which goes negative exactly when the
    loop is already behind, and raising there converts a missed frame into a
    crash. Feeding a negative tv_nsec to nanosleep(2) is EINVAL besides.

    So code written for CPython behaves identically, and code written against
    this will not port back unchanged. That asymmetry is the point of the rule,
    not an oversight -- and it is why the differential fixture does NOT include
    a negative row: it would be a row the oracle cannot run. }
  if seconds <= 0.0 then
    Exit;
  whole := Int(seconds);
  sec := Trunc(whole);
  nsec := Trunc((seconds - whole) * Double(NSEC_PER_SEC));
  { Rounding can land exactly on a full second; nanosleep(2) requires
    tv_nsec < 1e9. }
  if nsec >= NSEC_PER_SEC then
  begin
    nsec := nsec - NSEC_PER_SEC;
    sec := sec + 1;
  end;
  if nsec < 0 then
    nsec := 0;
  PalNanosleep(sec, nsec);
end;

end.

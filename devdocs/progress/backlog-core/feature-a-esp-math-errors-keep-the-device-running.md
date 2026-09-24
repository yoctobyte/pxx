---
prio: 60
track: A
summary: "ON ESP (TargetPlatform = PLATFORM_ESP, esp32c3/esp32s3, IDF and bare), NO MATH ERROR HALTS BY DEFAULT. The owner, 2026-09-24: an embedded device 'should (try) to keep running, even if whatever unexpected input (sensor etc) produces a math error. we should not halt.' Floats give NaN or Inf; ints give 0 or a saturated value. DONE for Pascal/C integer div/mod (0) and for NilPy: `//` and `%` give 0 (including bignums); `/`, math domain errors and range errors give IEEE inf/nan. The NilPy half is frankuser's reading of the principle. OPEN: the census residue in LOGBOOK (Trunc of an out-of-range float into a 32-bit int wraps; an uncaught exception on a c3 IDF build panics via ecall). Opt-in {$R+}/{$Q+} keep trapping. Desktop is untouched."
---

# ESP: math errors keep the device running

Decision: decide-int-div-zero-behavior-unification, section DECIDED 2026-09-24.

## Done

- 2026-09-24 (frankS): integer `div`/`mod` by zero give 0 on ESP, in Pascal and
  in C. Guards: test/test_esp_div_by_zero_yields_zero.pas and
  test/c_esp_div_by_zero_yields_zero.c, rows in `test-esp-idf`, both chips.
  Control: pinned v421 prints runtime error 200 on the first row.

- 2026-09-24 (frankS): NilPy on ESP. Integer `//` and `%` by zero give 0,
  including bignums (promocore BDivMod). `/`, float `//`, math.sqrt, log,
  asin and pow domain errors, math.exp/pow overflow and `0.0 ** -1` give IEEE
  inf/nan, with no raise. This is FRANKUSER'S READING of the owner's
  principle, not the owner's words. Guard:
  test/test_nilpy_esp_math_errors_keep_running.npy, run through nilpy-{c3,s3}
  build.sh in `test-esp-idf`. Control: pin v423 reboot-loops on c3. Desktop
  still raises CPython's exceptions (measured on each shape against CPython).
- Census (step 3), 2026-09-24, c3 and s3 identical. Pascal: nothing halts.
  NaN->int gives 0, and Inf or 1e30 into Int64 gives Int64 max. Residue is in
  LOGBOOK, not ticketed: Trunc(1e30) into a LongInt gives -1 (the low bits,
  not saturated), and an uncaught exception on c3 IDF panics via ecall and
  reboot-loops.

## Open (historical, closed above)

2. NilPy on ESP: `//` and `%` by zero give 0, and `/` by zero gives inf/nan
   with no raise. frankuser's reading, flagged as such. Note, measured
   2026-09-24 on DESKTOP: `7 // b` with a runtime int already gives Pascal's
   runtime error 200, NOT ZeroDivisionError, and `try/except
   ZeroDivisionError` cannot catch it. Only the literal `1 // 0` raises. That
   is a desktop NilPy bug in its own right (Track N).
3. Census of the other halting paths on ESP, then fix the cheap ones.

---
prio: 60
track: A
summary: "ON ESP (TargetPlatform = PLATFORM_ESP, esp32c3/esp32s3, IDF and bare), NO MATH ERROR HALTS BY DEFAULT. The owner, 2026-09-24: an embedded device 'should (try) to keep running, even if whatever unexpected input (sensor etc) produces a math error. we should not halt.' Floats give NaN or Inf; ints give 0 or a saturated value. DONE: Pascal/C integer div/mod by zero give 0 (DivZeroYieldsZero). OPEN: (2) on ESP, NilPy `//`/`%` by zero give 0 and `/` follows IEEE with no ZeroDivisionError. This is frankuser's reading of the principle, not the owner's words; desktop NilPy keeps raising. (3) A census of every other default path that halts or raises on ESP (Trunc/Round/Int of NaN/Inf, float->int overflow, math-unit domain errors, NilPy math.sqrt(-1)/log(0) ValueError), with the cheap ones fixed and the rest ticketed. Opt-in {$R+}/{$Q+} keep trapping. Desktop is untouched."
---

# ESP: math errors keep the device running

Decision: decide-int-div-zero-behavior-unification, section DECIDED 2026-09-24.

## Done

- 2026-09-24 (frankS): integer `div`/`mod` by zero give 0 on ESP, in Pascal and
  in C. Guards: test/test_esp_div_by_zero_yields_zero.pas and
  test/c_esp_div_by_zero_yields_zero.c, rows in `test-esp-idf`, both chips.
  Control: pinned v421 prints runtime error 200 on the first row.

## Open

2. NilPy on ESP: `//` and `%` by zero give 0, and `/` by zero gives inf/nan
   with no raise. frankuser's reading, flagged as such. Note, measured
   2026-09-24 on DESKTOP: `7 // b` with a runtime int already gives Pascal's
   runtime error 200, NOT ZeroDivisionError, and `try/except
   ZeroDivisionError` cannot catch it. Only the literal `1 // 0` raises. That
   is a desktop NilPy bug in its own right (Track N).
3. Census of the other halting paths on ESP, then fix the cheap ones.

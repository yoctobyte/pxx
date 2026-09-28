---
prio: 60
track: A
summary: "ON ESP (TargetPlatform = PLATFORM_ESP, esp32c3/esp32s3, IDF and bare), NO MATH ERROR HALTS BY DEFAULT. The owner, 2026-09-24: an embedded device 'should (try) to keep running, even if whatever unexpected input (sensor etc) produces a math error. we should not halt.' Floats give NaN or Inf; ints give 0 or a saturated value. DONE and RE-VERIFIED 2026-09-28 on C3 and S3 QEMU: Pascal/C integer div/mod give 0; NilPy `//` and `%` give 0 (including bignums) and `/`, math domain errors and range errors give IEEE inf/nan; an uncaught exception now reports itself before parking. Desktop re-verified unchanged (RE 200, exit 200). The NilPy half is frankuser's reading of the principle. Both census-residue items are closed, not open: the Trunc row is published by-design and NOT ESP-specific, and the uncaught-exception panic was fixed in 7eeb3d7552. Opt-in {$R+}/{$Q+} keep trapping. Desktop is untouched."
status: done
owner: frankz-e5
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
  NaN->int gives 0, and Inf or 1e30 into Int64 gives Int64 max.

- 2026-09-25 (frankD): the census residue was re-measured on v425 and BOTH
  halves left this ticket. See "The residue is closed" below.

- 2026-09-28 (frankz-e5): every wired row re-run and green. See "Verified" below.

## Verified 2026-09-28 (frankz-e5), compiler 0ded1e5d04c8

Each row run singly rather than through `make test-esp-idf`, which is a suite.
ESP rows are QEMU via `tools/esp_run.sh`; no silicon is needed for any of them,
because every claim here is about what the compiler emits.

| row | esp32c3 | esp32s3 |
| --- | --- | --- |
| `test_esp_div_by_zero_yields_zero.pas` | PASS | PASS |
| `c_esp_div_by_zero_yields_zero.c` | PASS | PASS |
| `test_esp_uncaught_exception_prints.pas` | PASS | PASS |
| `test_nilpy_esp_math_errors_keep_running.npy` | PASS | PASS |

Desktop control, x86-64, asserting the halt that ESP deliberately does not do —
`test_div_zero_re200`, both its rows, matching Makefile:16672-16673 exactly:

```text
14 2 -14
before
Runtime error 200 (division by zero)
exit=200
```

So the two behaviours are simultaneously true in one tree, which is the whole
point of the decision: the device keeps running, the desktop stops and says why.

Compiler identity, stated precisely because the binary moved twice while this
was being written: every row above was measured on `0ded1e5d04c8`, a sha256
prefix of the compiler BINARY (the same value `tools/esp_flash.sh` stamps into
its verdict lines, and the same binary frankb-12's v449 silicon runs used), and
that sha was computed at measurement time rather than inferred afterwards. Three
compiler commits landed on origin later the same day (`13f122a0ef` frozen-mode
string builtins, `a49f6f12c6`/`b1b51f5a0d` NilPy result typing and dynamic-array
results), none of them in an integer div/mod or float path. The rows are NOT
re-run for them, following the fleet practice of labelling a row with the
compiler it was witnessed on rather than chasing every pin.

Worth knowing about the NilPy fixture, because it is better built than most and
the reason is reusable: it derives its zero as `len(sys.argv) - len(sys.argv)`
so the compiler cannot constant-fold the division away, and its last line is
`continued`. A math-errors test whose last line is the last math call passes on
a board that printed the right answers and then died; this one asserts the
device SURVIVED.

## The residue is closed, and neither half was an ESP defect to fix

The old summary listed two open census-residue items. Both left this ticket
before I touched it, and re-running them would have been work against a
published decision.

1. **`Trunc` of an out-of-range float into a 32-bit int.** NOT ESP-specific.
   frankD re-measured on v425 and desktop gives the same answer, so it was moved
   to a by-design note, now at `docs/reference/known-issues.md:733`. Re-measured
   here on desktop x86-64 rather than taken on trust:

   | source | into `LongInt` | into `Int64` |
   | --- | --- | --- |
   | `1e30` | **-1** | 9223372036854775807 |
   | `-1e30` | **0** | -9223372036854775808 |
   | `nan` | 0 | 0 |

   and `1e30` into a `Word` gives 65535, into a `ShortInt` -1. That is the low
   bits of the saturated 64-bit value at every width, which confirms the
   published note's mechanism rather than just its headline. A float that does
   not fit the integer it is truncated into has no integer value; range-check
   the input. Not changed, deliberately: an ESP-only fix would contradict a
   published by-design row AND break "desktop is untouched".

2. **An uncaught exception on a c3 IDF build panicked via ecall.** Fixed in
   `7eeb3d7552`, which prints `Unhandled exception: <Class>: <Message>` from the
   main-body catch-all before the program parks. Guarded by
   test/test_esp_uncaught_exception_prints.pas on both chips, green above.

## Still open, and NOT this ticket's to answer

**Whether an ESP program should stop or restart after an uncaught exception has
not been decided; today it stops** (`docs/reference/known-issues.md:684`), and
under QEMU on C3 the interrupt watchdog then reboots it. That sits at an angle
to the owner's "we should not halt", so it is an owner decision and frankuser has
put it to him. It does not block this ticket, because on ESP a math error no
longer raises at all — it yields 0 or inf/nan — so a bad sensor value never
reaches the halt path. The tension is about exceptions in general, not about
math.

## A desktop NilPy defect this ticket must not take down with it

Measured 2026-09-24, on DESKTOP: `7 // b` where `b` is a runtime int gives
Pascal's runtime error 200, **not** `ZeroDivisionError`, and `try/except
ZeroDivisionError` cannot catch it. Only the literal `1 // 0` raises. That is a
desktop NilPy bug in its own right (Track N), and nothing on ESP depends on it.

It is recorded here because this ticket is where it was found, and that is a
problem: `decide-int-div-zero-behavior-unification.md:174` says the desktop
behaviour is "Tracked in feature-a-esp-math-errors-keep-the-device-running" —
this file — so resolving this ticket points that sentence into `done/`. Worse,
line 111 of the same decision states "**NilPy is already decided and correct**:
`7 // 0` raises `ZeroDivisionError`", which the measurement above contradicts for
every non-literal divisor.

No ticket filed: the month's rule is no new tickets unless release-blocking, and
this is a desktop NilPy behaviour on a paused project. Instead the measurement
and the decision-doc discrepancy are carried into `devdocs/progress/LOGBOOK.md`
as a pointer, so they survive outside a closed ticket, and frankuser has been
told so the owner can rule on the decision text. Same shape as the pointer
recorded at LOGBOOK 2026-08-31 (frankB): the finding belongs to the ticket, the
pattern does not, and a note nobody will re-read is not tracking.

## Log
- 2026-09-28 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

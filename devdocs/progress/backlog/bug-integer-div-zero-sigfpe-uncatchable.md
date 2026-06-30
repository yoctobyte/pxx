# Integer `div` / `mod` by zero aborts with SIGFPE (uncatchable)

- **Type:** bug (runtime / codegen — robustness) — Track A
- **Status:** backlog
- **Severity:** medium — FPC raises a catchable `EDivByZero`; here the process
  dies with SIGFPE (core dump, exit 136) and cannot be guarded with try/except.
- **Opened:** 2026-06-30 (Track B latent-bug sweep, against stable v97)

## Symptom

Integer division or modulo by a zero divisor terminates the process with a
hardware `SIGFPE` ("Floating point exception (core dumped)", exit 136). A
surrounding `try ... except` does **not** catch it:

```pascal
var i, z: integer;
begin
  z := 0; i := 7;
  try i := i div z;            { SIGFPE — process aborts here }
  except writeln('caught div'); end;
  writeln('after div');        { never reached }
end.
```

`i mod z` behaves identically. Both abort before any handler runs.

## Expected

FPC raises a catchable `EDivByZero` (integer div) / `EZeroDivide`, so robust code
can `try ... except` around user-supplied divisors. At minimum the abort should
be a clean runtime error, not a raw core-dumping SIGFPE.

## Likely cause

The backend emits a bare `idiv` with no zero-divisor guard, and no `SIGFPE`
handler is installed to convert the trap into a language-level exception. Either
(a) emit a pre-divide zero check that raises `EDivByZero`, or (b) install a
SIGFPE handler in the runtime that raises into the active exception frame.
Depends on the exception machinery; note also
[[bug-except-base-handler-misses-derived]] (a base `on E: Exception` handler
must be able to catch the raised `EDivByZero`).

## Track B impact

Libraries/demos must hand-guard every divisor (the calc demo already checks for a
zero denominator before dividing rather than catching). Acceptable workaround,
but it means no idiomatic `try/except` around arithmetic.

## Acceptance

- `i div 0` / `i mod 0` raise a catchable `EDivByZero` (caught by
  `on E: EDivByZero` and by `on E: Exception`); `after div` reached.
- Non-zero divisors unaffected; cross targets behave consistently.
- Regression test (`test/test_div_zero_raises.pas`) wired into `make test`;
  self-host stays byte-identical.

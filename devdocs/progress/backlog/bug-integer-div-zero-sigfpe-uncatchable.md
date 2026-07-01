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

## Scoping note (2026-07-01, investigated but not attempted)

Looked at what "emit a pre-divide zero check that raises `EDivByZero`" would
actually take before writing any code, since the surface area turned out
bigger than it looks:

- `Exception` (and any subclass like `EDivByZero`) is **not** a compiler-known
  type — it's plain Pascal in `lib/rtl/sysutils.pas`, only registered as a
  real class (VMT, REC id) when a program `uses sysutils`. `IR_RAISE`
  (`compiler/ir_codegen.inc:4373`) just stores an already-constructed object
  handle + a compile-time-known REC id into `BSS_EXC_OBJ`/`BSS_EXC_CLS` and
  jumps into the unwinder — it has no path today for "the codegen itself
  needs to allocate+construct an exception object" independent of a user
  `raise <expr>` AST node. Every existing raise site starts from user source
  (`AN_RAISE`, `compiler/ir.inc:4282`) evaluating a real constructor-call
  expression.
- So a pre-idiv zero check would need to *synthesize* the equivalent of
  `raise EDivByZero.Create('...')` from inside arithmetic codegen: allocate
  the object, stamp its VMT, run the constructor (string-message field
  included, so ARC-aware), fill `BSS_EXC_OBJ`/`BSS_EXC_CLS`, then call
  `ExcRaiseAddr` — all while depending on `sysutils` being `uses`d (a program
  with no `uses sysutils` has no `Exception`/`EDivByZero` type to construct
  in the first place, so the guard would need a fallback path — e.g. keep
  the current SIGFPE/Halt behavior — for that case).
- Grepped for any existing "codegen-inserted runtime check raises a catchable
  exception" precedent (range checks, nil-deref, stack overflow, etc.) —
  found none. Every other runtime-detected failure in this codebase today is
  either a hardware trap (this one) or a `Halt`-based compile/runtime error,
  never a synthesized `raise`. So there's no pattern to mirror; this would be
  the first of its kind.
- Net: this is a real architecture decision (should the compiler always link
  a minimal builtin exception base regardless of `uses sysutils`? should
  codegen gain a "synthesize and raise a runtime exception" primitive
  reusable by future checks like range/nil-deref?) rather than a local
  one-file fix. Parking per the "big or needs discussion" rule instead of
  guessing at an architecture overnight solo. Whoever picks this up should
  probably decide the builtin-exception-availability question first — it
  likely affects [[bug-i386-try-except-segfault]]'s `E.Message`-empty
  observation too (both are exception-machinery edges).

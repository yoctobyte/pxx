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

## Scoping note 2 (2026-07-01, a smaller fallback considered, also not attempted)

Reconsidered the ticket's own "at minimum" fallback goal — a clean abort
(print a message, `exit(1)`) instead of a raw core-dumping SIGFPE, WITHOUT
full catchable-exception integration. This sidesteps the architecture
question above entirely (no `Exception`/`uses sysutils` dependency needed —
just a portable `PXXDivZeroAbort`-style runtime helper, the same shape as
existing helpers like `PXXDynSetLen`), so it looked promising at first.

Sized it before writing code: div/mod codegen isn't one call site per
target, it's roughly 10+ across all 6 backends —
- 32-bit-word div/mod: `ir_codegen.inc` (x86-64), `ir_codegen386.inc`,
  `ir_codegen_arm32.inc`, `ir_codegen_aarch64.inc`, `ir_codegen_riscv32.inc`,
  `ir_codegen_xtensa.inc` each have their own inline `idiv`/`sdiv`/`udiv`
  emission (different instruction encodings, different register
  conventions, xtensa additionally branches on `XtensaSoftDivide` for a
  software-divide call vs hardware).
- 64-bit div/mod on the 32-bit targets is a SEPARATE code path again on
  each of i386/arm32/riscv32/xtensa (`EmitIDivMod64Core_386`,
  `EmitIDivMod64Arm32`, `EmitIDivMod64RISCV32`, `EmitIDivMod64Xtensa` —
  software long-division routines, not a single hardware instruction).

That's core arithmetic — the single most heavily-exercised operation in any
program — on every target, each needing a zero-check correctly inserted
into already-delicate assembly-emission code (getting a register/flag
subtly wrong here wouldn't just miss the ticket's goal, it could silently
corrupt ordinary division results). Wide blast radius for a solo overnight
pass with no one to review; parking this narrower framing for whoever
picks it up next rather than rushing ~10 site edits across 6 backends at
this hour. The good news: this fallback version genuinely doesn't need the
architecture decision above, so it's a smaller, well-defined, mechanical
(if wide) task once someone has a clear multi-hour block for it.

## Scoping note 3 (2026-07-02, re-examined the x86-64-only slice specifically)

Reconsidered once more with fresh eyes, this time actually counting the
real `idiv` call sites in `ir_codegen.inc` (x86-64) rather than estimating:
there are only **3** total (`grep -c idiv`), and 2 of those are inside a
rare Variant-arithmetic helper (dynamic-typed `div`/`mod` on a `Variant`
value, not the common path). The ordinary integer `div`/`mod` codegen most
programs actually hit is really **one** code site
(`ir_codegen.inc` ~2598-2612, the `tkDiv`/`tkMod` cases of the main binop
dispatch). So "x86-64 only" is much narrower than the "~10+ sites across 6
backends" framing above suggested when scoped to just this one target —
worth recording precisely rather than leaving the wide estimate as the
only data point.

That narrower count does NOT change the parking decision, though, for two
reasons independent of line count:

1. **This would still be the first codegen-inserted runtime safety check
   of any kind in the whole compiler** (confirmed again this pass: grepped
   for any existing array-bounds-check / nil-deref-check / similar
   precedent anywhere in `ir_codegen.inc`/`ir.inc` — genuinely none exist;
   every runtime-detected failure today is a raw hardware trap). Even the
   "no message, just `exit(1)`" minimal version is a new architectural
   category, not a bug-fix-shaped change — the kind of precedent worth the
   user weighing in on (does this open the door to bounds-checking, etc.,
   or should it stay a one-off?), not something to decide by fiat overnight.
2. **A single-target fix creates a real inconsistency**: x86-64 would get a
   clean abort while i386/arm32/aarch64/riscv32/xtensa still raw-SIGFPE-crash
   on the exact same source program — an asymmetry across targets that
   itself deserves a decision (ship it now for the primary target and file
   the rest as follow-ups? or hold for parity?) rather than silently
   introducing target-dependent behavior for the same Pascal semantics.

Still parked; recording the narrower, precisely-counted x86-64 scope so a
future pass (or the user) can weigh the real tradeoff (small code footprint
vs. real precedent-setting/consistency questions) instead of over- or
under-estimating the effort.

## Resolution — 2026-07-02, Track A (x86-64 slice landed after user discussion)

Discussed live with the user (the architecture questions the two parking notes
raised are now answered):

- **Detection**: pre-divide check (`test rcx,rcx; jnz +5; call ...`) at the one
  x86-64 div/mod binop site. Default ON, FPC-style; `--no-div-check` opts out
  (restores the raw SIGFPE). 2 instructions next to a ~20+-cycle idiv.
- **No sysutils dependency** (user requirement "stick to builtins"): the check
  calls `PXXDivZero` in builtinheap (message + Halt(200)) when that unit is in
  the program, else a unit-free emitted stub `Div0StubAddr` (raw write +
  exit_group syscalls) — both print `Runtime error 200 (division by zero)`,
  exit code 200, matching FPC-without-sysutils behavior.
- **Catchable-exception upgrade path built in but not populated**:
  `PXXDivZeroHook` procvar in builtinheap mirrors FPC's System-unit
  ErrorProc/hook design (FPC also only raises EDivByZero when sysutils'
  initialization installs hooks at startup — it is NOT a compile-time import
  check). Which unit installs the hook here (builtin-resident Exception vs
  never) is deliberately deferred to
  [[decide-int-div-zero-behavior-unification]].
- **Variant div/mod**: PXXVarBinOp is Pascal compiled by the same backend, so
  its internal div/mod got the check for free.
- **Floats**: explicitly out of scope (user: quiet IEEE inf/NaN propagation is
  the preferred default for real-world data; value pre-checks are the wrong
  tool for floats anyway — overflow/denormals need the FPU mask mechanism).
  Filed [[feature-float-exception-mask-control]] (blocked on
  [[feature-signal-handlers]]).
- **Remaining targets** (i386 SIGFPE, arm silent-0, riscv -1) + the still
  unguarded `Low(Int64) div -1` overflow trap + default/switch polarity:
  folded into [[decide-int-div-zero-behavior-unification]] (low prio, decision
  ticket capturing the discussion's pros and cons).

Gate: test/test_div_zero_re200.pas (div + mod paths, exit-code 200 + message
oracle, non-zero divisors sanity) wired into make test; full suite green;
self-host converged (3-gen, codegen change) byte-identical.

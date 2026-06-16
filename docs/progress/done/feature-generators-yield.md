# Generators and `yield` (the coroutine on-ramp)

- **Type:** feature
- **Status:** done
- **Blocked-by:** feature-unified-heap-allocator
- **Opened:** 2026-06-16

## Why generators first

Generators are the gentle on-ramp to async/coroutines: a one-way, consumer-driven
producer (`yield v` → consumer pulls via `for x in g()`), simpler than symmetric
coroutines, immediately useful (iterators, lazy sequences, token streams), and
they exercise the same stack-switch machinery a scheduler would — with far less
runtime. Build this before the scheduler/reactor in feature-async-coroutines.

Library/user-only: FPC has no generators, so the FPC/PXX boundary keeps them out
of `compiler/` (see feature-fpc-vs-pxx-feature-boundary). No self-host constraint
on the feature itself.

## Design decision — BOTH lowerings, one surface, `; generator;` directive

We want **both** a stackful and a stackless implementation (decided 2026-06-16).
The **language surface is identical** for either — `; generator;`, `yield`,
`for x in g`, the iterator protocol — only the lowering differs. Implement the
iterator protocol + `for-in` ONCE; plug in two lowerings. `for-in` never cares
which strategy a generator used.

### Surface — a Pascal directive (not a Python `@decorator`)

`generator` is a routine directive, like `inline` / `cdecl` / `assembler`
(minimal lexer change — same machinery):

```pascal
function Squares(n: Integer): Integer; generator;            { auto strategy }
function Tokens: Integer; generator; stackless;              { force stackless }
function Walk(t: TTree): Integer; generator; stackful;       { force stackful  }
```

### Strategy selection

- `; generator;` alone → **auto**.
- `; generator; stackful;` / `; generator; stackless;` → forced.
- **Auto rule (documented, predictable):** stackless when every `yield` is in
  transformable control flow — top-level body, straightline / `for` / `while` /
  `if` — and no `yield` crosses a call boundary or sits in a `try`. Otherwise
  stackful. Force-`stackless` on an ineligible body → clear compile error.

### Two lowerings

- **Stackful:** the iterator wraps a coroutine (`CoSwitch` + a small heap stack).
  `yield` works anywhere. Shared with feature-async-coroutines.
- **Stackless:** the compiler transforms the body into a state-machine record
  (resume point + saved locals); no heap stack, restricted yield placement.
  Ideal for ESP32 (tiny RAM).

### Validation (the "complain" rules)

- `; generator;` but **no `yield`** in the body → error.
- `yield` **without** `; generator;` → error ("yield outside a generator").
- `yield` value type ≠ declared result type → error.
- `yield` inside `try`/`finally`/`except` → error in v1 (accepted restriction;
  also disqualifies stackless eligibility).

### Self-host

The `generator`/`yield` keywords + transform live in the compiler (FPC compiles
that source fine — it just never sees a `generator` *used* in `compiler.pas`).
FPC/PXX boundary: add the feature; never use it in `compiler/`.

## v1 lowering — stackful (reuse `CoSwitch`)

A generator is a coroutine with a constrained protocol. Build it on the same
per-target context-switch primitive that feature-async-coroutines needs:

```
TCoroCtx = record sp: Pointer; ... end;
procedure CoSwitch(var from: TCoroCtx; const to: TCoroCtx);  { the only asm }
```

- `yield v` saves the generator's value somewhere shared and `CoSwitch`es back to
  the consumer; `for x in g` `CoSwitch`es into the generator for the next value.
- A small heap stack per live generator (fixed, configurable, canary-guarded).
- **`yield` works anywhere** (loops, nested calls) — no transform restrictions.

Pro: minimal compiler work (no CPS/state-machine transform); the expensive part is
six small asm stubs (one per target — x86-64/i386/aarch64/arm32/riscv32/xtensa),
and the codegen already has inline asm + per-target encoders.

### Accepted restriction (v1)

**Forbid `yield` inside `try`/`finally`/`except`** with a clear compile error.
This sidesteps the exception-frame swap (PXX exceptions are setjmp-style with a
per-stack `BSS_EXC_TOP` chain; cross-stack `raise` would otherwise unwind the
wrong frames). Lift the restriction later, together with the coroutine work that
needs the full exc-top save/restore.

## Iterator protocol (do this generally)

Define a small iterator contract — e.g. `function Next(var v: T): Boolean` (or
`MoveNext`/`Current`). `for x in g` calls it until False. A generator is just one
implementation; make arrays / collections implement the same contract so `for-in`
becomes a general feature, not generator-specific. Two wins for one.

## Surface

```pascal
generator function Squares(n: Integer): Integer;
var i: Integer;
begin
  for i := 1 to n do yield i * i;
end;

var x: Integer;
for x in Squares(5) do writeln(x);   { 1 4 9 16 25 }
```

- New `yield` keyword (lexer/parser) — only legal in a `generator`-marked routine.
- `for <var> in <generator-call>` drives the iterator protocol.

## Stackless backend (second lowering — planned, not optional)

Transform a stackless-eligible generator into a state-machine record + iterator
(resume point + saved locals). No asm, no heap stack — ideal for ESP32 (tiny RAM).
Cost: `yield`-placement restrictions (top-level / simple loops, no yield across a
call boundary or in a `try`) and the transform itself. Behind
`; generator; stackless;` first, then folded into auto-selection. Same surface as
stackful — no grammar change to add it.

## Phasing

1. `CoSwitch` asm primitive (shared with feature-async-coroutines) on x86-64,
   then all six targets. Prove a two-context ping-pong; self-host fixedpoint
   holds.
2. **v1 surface + stackful backend:** `; generator;` directive + `yield` +
   iterator protocol + `for-in` + all validation rules (no-yield, yield-outside,
   type-mismatch, no-yield-in-try). Stackful lowering only.
3. Make arrays / collections implement the same iterator protocol (general
   `for-in`). **Split out → feature-for-in-iteration.md** (additive; generators
   do not depend on it).
4. **v2 stackless backend** behind `; generator; stackless;` — the state-machine
   transform. Same surface.
5. **v3 auto-selection** (eligible → stackless, else stackful); keep the force
   overrides.
6. (Later) lift the `yield`-in-`try` restriction together with the coroutine
   exc-top save/restore work.

## Log

- 2026-06-16 — **Phase 1 (CoSwitch) DONE on x86-64.** `coroutine_emit.inc`
  emits a bare `CoSwitch` stub (saves rbp + rbx + r12–r15 + `BSS_EXC_TOP` onto
  the current stack, swaps `rsp` via `[pfrom]`/`[pto]`, restores, `ret`).
  **TCoroCtx layout = just `{ sp: Pointer }`** — all callee-saved state and the
  per-stack exception-chain head live ON the switched stack, so a TCoroCtx is a
  single saved sp. Exposed via the low-level `__pxxcoswitch(pfrom, pto)`
  intrinsic (`AN_COSWITCH` → `IR_COSWITCH` → `call CoSwitchAddr`), recognised in
  both the expression and statement parser paths. Runtime stub emitted before
  the main body, gated on a token scan; pulls in the exception runtime so the
  exc slot exists. `test/test_coswitch.pas` proves a two-context ping-pong with
  a hand-built initial frame; wired into `test-core`. Fixedpoint byte-identical
  (procs=882). Commit `bad554a`.
  - Initial-stack frame the first switch-in pops (low→high):
    `exc_top(0), r15, r14, r13, r12, rbx, rbp, retaddr`. `rsp` at entry must be
    `≡ 8 (mod 16)`: align top to 16, `-8`, then `-64` for the 8 qwords.
  - LANDMINE found while building the test: **`not 15` mis-evaluated to `14`**
    in PXX — `not` was always logical (xor bit 0) regardless of operand type.
    **FIXED 2026-06-16 (commit 606abec):** parser now types `AN_NOT` from the
    operand node's own type and promotes to bitwise complement for true integer
    operands (ord 1, 7..16); Boolean/char/pointer/unknown stay logical. Matches
    FPC; fixedpoint byte-identical. (The test's align-down still uses
    `top - (top mod 16)`, which is fine.)
  - DESIGN NOTE for Phase 2: PXX does **not** support calling through a
    procedure-typed variable with arguments (`p(42)` is a parse error — only
    `p := @Proc` / method-ptr round-trips exist). So a generic library
    trampoline `CoCreate(bodyPtr, arg)` cannot call the body. The generator's
    entry + argument wiring must be **compiler-emitted** (the compiler knows the
    body proc and its params and can emit `mov rdi,<instance>; call <body>`
    directly). The library supplies the protocol pieces (CoYield/CoNext/heap
    stack), but the entry/arg glue lives in the surface lowering. Phase 2 is
    therefore a compiler-surface effort (grammar change → bootstrap reseed), not
    cleanly splittable into a library-only sub-phase.
  - TODO next: Phase 2 surface (`generator`/`yield`/`for-in` + iterator
    protocol) with compiler-emitted entry/arg glue + the PXX-only RTL helpers
    (heap stack alloc + canary, exhaustion switch-back & stack free). Then port
    CoSwitch to the other 5 targets (mechanical, mirror exception_emit.inc +
    add IR_COSWITCH lowering per backend). When a library unit (not the main
    file) uses `__pxxcoswitch`, also trigger `EnableCoroutineRuntime` from the
    per-unit token scan in `ParseUsesUnit` (mirror the tkTry/tkRaise scan).

- 2026-06-16 — **Phase 2 (surface) DONE on x86-64** (commits 0e2a57a + fix
  ca0b8df). `function F(...): Integer; generator;` + `yield E` + `for x in F(a)`
  all work end-to-end; the acceptance test (`Squares(5)` → 1 4 9 16 25) and
  multi-param generators (`Range`, `Fibs`) pass. Validation rules all fire
  (no-yield, yield-outside, yield-in-try, >4 params, non-x86-64 target, forced
  stackless). `test/test_generator.pas` wired into test-core. Bootstrap
  fixedpoint byte-identical (procs=889); **cross-bootstrap i386+aarch64+arm32
  byte-identical**; full `make test` green.
  - Lowering (minimal custom codegen): a generator function compiles as a
    coroutine body — hidden self-pointer local; body prologue `mov [self],rbx`
    (instance handed off in the initial frame's rbx slot) then per-param loads
    from the instance **at each param's own width** (slots are size-packed — a
    qword store clobbers the adjacent param; that was a real bug, found via
    raw-byte disasm); `yield E` → AN_YIELD/IR_YIELD (store current + CoSwitch);
    fall-off epilogue marks done + CoSwitches back (never returns). `for-in`
    desugars to `CoAlloc(@F,n,a0..a3)` + `while CoNext do x:=CoCurrent; BODY` +
    `CoFree`, all in `lib/rtl/coroutine.pas` (PXX-only).
  - LANDMINES (both bit cross-bootstrap, NOT x86-64 fixedpoint — so `make
    bootstrap` alone misses them; always run `make cross-bootstrap`):
    (1) **No local fixed arrays in compiler.pas** — i386/arm32/aarch64 codegen
    only supports ordinal/pointer/string locals. Use scalar locals + helpers.
    (2) **`not` typing trap** (the original all-logical comment was right): PXX
    tags some boolean `AN_BINOP`/`AN_CALL` results as tyInteger, so the bitwise
    `not` promotion must be restricted to `AN_INT_LIT`/`AN_IDENT` operands only.
  - Requires `uses coroutine;` (v1). Direct (non-for-in) generator calls are not
    guarded yet — would run the body via the normal ABI with garbage self.
  - TODO: port CoSwitch + generator codegen to the other 5 targets; lift
    yield-in-try; `generator function` prefix form; stackless backend (v2).

- 2026-06-16 — **Phase 4 (v2 stackless backend) DONE — `; generator; stackless;`
  on ALL targets, zero per-target asm** (commit 147b3a0). It's a compiler
  TRANSFORM, not asm: the body becomes a state-machine *step function* with the
  ABI `function(self): Boolean` (has-next); persistent params/locals live in a
  heap instance (offsets `SL_OFF_* = CO_OFF_*`, so for-in reads value/done the
  same for either strategy), restored on entry and saved at each yield. `yield E`
  → set current/state, checkpoint locals, `Result:=True; Exit;`, resume label;
  re-entry dispatches `if state=k goto Lk`. `for`/`while`/`if` containing a yield
  are flattened to goto/label form; yield-free statements pass through verbatim.
  Everything lowers through the shared cross-target IR → runs on x86-64 + i386 +
  arm32 + aarch64 (all verified, output identical), proving the no-asm claim
  (i386/arm32/aarch64 under QEMU). Ideal for ESP32 (no heap stack, no CoSwitch).
  - Surface/validation: `stackless` is now a real directive (was a hard error).
    Errors fire for stackless-without-generator, no-yield, and ineligibility —
    yield is only allowed at top level / `for` / `while` / `if`; yield in
    `try`/`case`/`repeat`/`with` is a clear compile error. Forced only (auto
    selection is v3, deliberately deferred).
  - for-in unified (option (a)): `ParseForInGeneratorAST` branches on
    `ProcIsStackless` — stackful → `CoAlloc`/`CoNext`; stackless → `SlAlloc` +
    a *direct* call to the step fn in the loop (PXX can't call a stored fn-ptr
    with args, but the compiler knows the proc). `SlCurrent`/`SlFree` are the
    shared-shape reads. RTL: `lib/rtl/slgen.pas` (`SlAlloc/SlGet/SlSet/SlCurrent/
    SlFree`) — pure Pascal, all targets, NO `__pxxcoswitch` dependency (so it
    works where coroutine.pas's x86-64 CoSwitch can't). Requires `uses slgen;`.
  - Implementation notes / landmines:
    (1) Step-call ABI: declared params become persistent locals but stay ABI
        params; the for-in call **pads to ParamCount with zero args** — the
        internal x86-64 call codegen pops `ParamCount` registers, so a short arg
        list unbalances the stack (corrupt return addr → SIGSEGV; that was the
        first crash found).
    (2) Save/restore enumerate ONLY the generator's own scope
        (`CurGenScopeBase..SymCount`), never globals — `SymGenSlot` defaults to 0
        (a valid slot index) for syms not created via AllocVar/AllocParam, so a
        global like `StdErr` leaked into the restore and produced
        `cannot assign to constant`. `SymGenSlot` is now `-1`-initialised in
        AllocVar/AllocParam AND the enumeration is scope-bounded.
    (3) Synthetic labels: AN_LABEL/AN_GOTO gained a name-free direct form
        (`ASTSOffset = -1` sentinel, `ASTIVal` = GotoLabel slot index) so the
        transform reuses the existing goto machinery without inventing token-char
        names.
    (4) v1 restriction: only ordinal/pointer-sized locals persist (managed/
        aggregate locals across a yield would need per-element ARC — deferred).
  - Bootstrap byte-identical (procs=912); **cross-bootstrap i386+aarch64+arm32
    byte-identical**; full `make test` + `make test-i386` green. test wired:
    `test/test_stackless_gen.pas` (Squares/Range/CountDown(downto)/EvensUpTo
    (while+if)/Three(straightline)/reuse) in test-core + test-i386.
  - TODO: v3 auto-selection (eligible→stackless else stackful, keep force
    overrides); port the *stackful* CoSwitch to the other 5 targets; lift
    yield-in-try; managed-typed yields/locals in stackless.

## Post-Phase-4 design notes (managed types, yield-in-try, next steps)

Decision 2026-06-16: **async next** (port the stackful CoSwitch + scheduler),
before stackless auto-selection (v3) and before lifting any restrictions.
Auto-selection is cheap and additive — fold it in after the lowerings stabilise.

### Managed types in a stackless generator — how hard

Two independent questions:

- **(A) Managed *yield* type** (`generator: AnsiString` / dyn-array element):
  *moderate.* The yielded value sits in the instance `CURRENT` word; today it's a
  raw machine word. For a managed value it must be a fresh **owned** reference:
  retain on `yield` (store into CURRENT), release the previous CURRENT each
  for-in step, release the last CURRENT at `SlFree`. Reuses the existing
  `AnsiStrRetain/Release` addrs + the per-element ARC helpers. ~1–2 days, no
  structural change. Loop var `x` then gets a borrowed/retained copy per the
  normal managed-assign path.

- **(B) Managed *locals* that persist across a yield** (`var s: AnsiString` live
  over `yield`): **hard, and it fights the current model.** The stackless design
  save/restores each persistent local as a machine word at the step boundary,
  but the step function returns normally on every yield — so its epilogue runs
  managed-local cleanup (release) on that local, while the *same pointer* is
  saved in the instance for the next resume → use-after-free. Fixing it needs one
  of:
    1. **Borrow semantics:** the instance OWNS the managed slots; stack locals are
       borrows; suppress the step epilogue's release for persisted managed locals;
       `SlFree` releases them. But the body's own ARC on `s := s + 'x'` assumes
       the local owns its ref — so in-body managed assignments would
       double-free / mismatch unless they too are rewritten to operate on the
       owning slot.
    2. **Redirect managed locals to instance fields:** rewrite each managed-local
       `AN_IDENT` to an instance field access and make the instance a real
       *managed record* (RTTI + zero-init + whole-record release at `SlFree`).
       Correct, but it's the invasive AST-rewrite the save/restore model was
       chosen to avoid, and it ties into the zero-init contract + RTTI.
  Either path is several days and risky.

  **Recommendation:** don't chase managed locals in *stackless*. The **stackful**
  backend gets them almost for free — a coroutine runs on a real stack, so
  managed locals live there with ordinary ARC and *no* save/restore. So:
  managed-heavy generators → stackful; stackless stays the lean ordinal/pointer
  path (its niche is embedded/ESP32, where you wouldn't lean on managed types).
  Revisit stackless-managed only if a concrete need appears, and start with (A).

### yield-in-try

- **Stackless:** keep forbidden **permanently**. PXX exceptions are setjmp-style
  with the jmp_buf/frame on the *stack*; a stackless step returns between yields,
  so a try-frame straddling a yield can't survive (its frame is on the transient
  step stack). Not a v1 limitation — a structural one for this lowering.
- **Stackful:** liftable, together with the coroutine `BSS_EXC_TOP` save/restore
  (the exc-chain head is per-stack). Do it as part of the async arc.

## Acceptance

`for x in g()` over a `generator` routine yields the correct sequence, suspends/
resumes across loop iterations, frees its stack at exhaustion; `yield` inside a
`try` is a clear compile error; self-host fixedpoint + cross-bootstrap unaffected
(library-only feature).

## Log (close)
- 2026-06-16 — **moved to done/.** Both lowerings ship: stackless on all 4
  targets, stackful on x86-64. Optional follow-ups (v3 auto strategy selection;
  porting the *stackful* generator codegen to cross targets — redundant since
  stackless already covers them; managed yields/locals in stackless) are minor.
  `; generator;` / `yield` / `for-in` work end-to-end.

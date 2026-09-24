---
prio: 43  # auto
---

# DECIDE: unify integer div/mod-by-zero behavior across targets

- **Type:** decision (low priority) — Track A
- **Status:** done
  the signal/exception stack ([[feature-signal-handlers]]) matures.
- **Opened:** 2026-07-02, capturing the user design discussion so the eventual
  decision starts from the recorded trade-offs.

## Current state (after the x86-64 slice landed, v135)

| target | `i div 0` today |
|---|---|
| x86-64 | pre-divide check → `Runtime error 200`, exit 200 (`--no-div-check` restores raw SIGFPE) |
| i386 | raw SIGFPE core dump |
| arm32 / aarch64 | hardware yields **0**, silently (ARM spec) |
| riscv32 | hardware yields **-1** (all ones), silently (RISC-V spec) |
| xtensa | hardware divide traps; software divide (LX6) undefined-ish |

## Positions recorded (2026-07-02 discussion)

- **User**: "returning zero is a sane result" — perspective from real-time
  measurement data where inputs go out of bounds inside complex math;
  abort-on-math-error is a theorist's default, not a practitioner's. Ints are
  acknowledged as different from floats, and riscv's -1 is the real outlier
  (neither a sane value nor an error). Halting should at minimum be behind a
  compiler switch (that exists now: check is default-on, `--no-div-check`
  opts out — whether that polarity is right is part of this decision).
- **FPC parity** (we want to be able to emulate closely, defaults may differ):
  FPC checks unconditionally (no switch at all) → RE 200; with sysutils in the
  uses closure its initialization installs hooks converting RE→ raised
  `EDivByZero`. The PXXDivZeroHook in builtinheap mirrors exactly that design
  and is ready for a future exception-providing unit to install into.

## Options on the table

1. **RE 200 everywhere** (extend the pre-check to the other 5 backends, ~9
   sites incl the 64-bit soft-div helpers on 32-bit targets): FPC-parity,
   consistent, kills the ARM silent-0 / riscv -1 divergence.
2. **Defined result everywhere** (e.g. `x div 0 = 0` by decree, check emits a
   cmov/select instead of a call): user's "sane result" position; cheap;
   diverges from FPC unless behind the emulation switch.
3. **Switchable semantics**: `--div-zero=error|zero|trap` (or directive) —
   both camps served; more surface to test per target.
4. **Catchable exception**: needs an exception-class home that is not
   sysutils (user: prefer builtins) — i.e. move/define a minimal
   Exception/EDivByZero in builtin, or wait for
   [[feature-emission-size-dce]] so carrying it is free. Hook mechanism
   already in place either way.

## Also unguarded today (fold into whichever option wins)

- `Low(Int64) div -1` / `mod -1`: x86 idiv still SIGFPEs (overflow trap, not
  zero divisor). FPC raises RE 215 (overflow). Either a second compare in the
  check or the signal handler catches it.

## Acceptance (of the decision, not code)

A written choice among the options (or a hybrid), with default + switch
polarity + FPC-emulation story fixed; implementation tickets then follow
per target.

## DECIDED 2026-07-20 — Option 1, RE 200 everywhere

**User's call: 1.** Integer division by zero raises RE 200 on every target.
Extend the existing x86 pre-check to the other five backends (~9 sites,
including the 64-bit soft-div helpers on 32-bit targets).

This kills the divergence that made the current state indefensible: x86 raises,
ARM silently yields 0, riscv yields -1. A silent wrong answer that differs per
target is exactly the bug class this project exists to hunt, and it is also
FPC-parity, so it costs nothing in compatibility.

**Fold in the unguarded overflow case:** `Low(Int64) div -1` / `mod -1` still
SIGFPEs on x86 (overflow trap, not zero divisor); FPC raises RE 215. Handle it
in the same pass — either a second compare in the check or via the signal
handler — rather than leaving a second silent divergence behind.

Rejected: 2 (defined result) diverges from FPC for no gain now that the check
is being written anyway; 3 (switchable) is surface to test per target for a
question with one right answer; 4 (catchable) needs an exception-class home
outside sysutils and can be layered on later — the hook mechanism already
exists.

## Log
- 2026-07-20 — DECIDED by the user; see the DECISION section above. Implementation follows in its own tickets.

## 2026-08-04 — measured data for the PROMO layer, and the position restated

Still **postponed** by the user; recorded only so the eventual decision starts
from measurements rather than recollection. Nothing was changed.

### `PromoInt` div/mod by zero, measured today

| target | tier | `x div 0` |
|---|---|---|
| x86-64 | inline | `Runtime error 200`, exit 200 |
| x86-64 | inline, `0 div 0` | `Runtime error 200` |
| x86-64 | heap (2^70) | `Runtime error 200` |
| **i386** | inline | **4294967295, exit 0 — SILENT** |

So the promotable-int layer inherits the same cross-target split the integer
table above documents, and i386 adds a fourth flavour to the list: not a trap,
not 0, not -1, but 2^32-1. Worth noting when option 1 ("RE 200 everywhere") is
costed — the promo runtime is ordinary Pascal compiled by pxx, so it follows
whatever the backends do rather than having a policy of its own.

**NilPy is already decided and correct**: `7 // 0` raises `ZeroDivisionError`,
byte-identical to CPython, because the frontend checks before promocore is
reached. Whatever this ticket settles for Pascal, the Python frontend keeps
Python's answer.

### The user's position, restated 2026-08-04

- **`0/0 == 1` by definition.** The confusion the position is aimed at is people
  reading a LIMIT where there is only a zero: `lim x→0` of something is not the
  value at zero, and the two get conflated.
- The float cases are **already settled and correct**: `1/0 = +Inf`,
  `1/-0 = -Inf`, `0/0 = NaN` — verified today at both targets, IEEE throughout.
- The blocker remains that **CPU behaviour differs** and there is no pragmatic
  forcing case yet. Postponed until one appears, deliberately.

(The float VALUES are right; printing one is not — `writeln` of a non-finite
Double hangs. That is a plain bug, not a policy question, and is filed as
[[bug-a-writeln-of-a-non-finite-double-hangs]].)

## DECIDED 2026-09-24: ESP returns 0; desktop keeps RE 200

**This supersedes the 2026-07-20 "RE 200 everywhere" FOR ESP ONLY.** Desktop and
hosted targets (x86-64, i386, aarch64, and arm32 and riscv32 under Linux) keep
runtime error 200 as before.

The owner's words, relayed by frankuser on 2026-09-24, in order:

> not halting on divby zero is desired behaviour, see relevant discussion about embedded

> on math errors i rather have NaN propagating

> range check is not an issue. especially not on esp. just code overhead.

> return 0 on esp, keep RE 200 on desktop

> the big distinction is a desktop app under an OS. and an embedded device that should (try) to keep running, even if whatever unexpected input (sensor etc) produces a math error. we should not halt.

The "relevant discussion about embedded" is the 2026-07-02 position recorded at
the top of this file ("returning zero is a sane result", from real-time
measurement data where inputs go out of bounds).

**What is built (frankS):**
- ESP means `TargetPlatform = PLATFORM_ESP`: esp32c3 and esp32s3, IDF and bare.
- Integer `div`/`mod` by zero gives 0, in Pascal and in C (C calls it UB, so 0
  is legal). This covers 32- and 64-bit, signed and unsigned, and the compound
  C forms.
- Mechanism (`DivZeroYieldsZero`, symtab.inc): the existing per-divide zero
  test, on zero, sets dividend := 0 and divisor := 1 and falls into the divide.
  The divide never sees a zero, so xtensa's QUOS cannot raise
  IntegerDivideByZero. There is no call and no builtinheap.
- Measured cost: about 20 B/site on esp32s3 and 24 B/site on esp32c3, with no
  fixed cost. The runtime-error route it replaces pulled builtinheap for
  PXXDivZero: 291 B -> 24,123 B of code for one `div` in an otherwise
  runtime-free esp32s3 program, and 500 B -> 33,876 B on esp32c3.
- `--no-div-check` still means raw hardware everywhere. Measured on esp32c3:
  -1 and the dividend (the RISC-V rule). On esp32s3 this build computes
  LongInt/Int64 division in the software core (no QUOS in the object), which
  gives the same -1 and dividend and does not trap.
- Opt-in checks ({$R+}, {$Q+}) keep trapping. The programmer asked for those.

**frankuser's reading of the principle, NOT the owner's words:** on ESP, NilPy
`//` and `%` by zero also give 0, and `/` by zero follows IEEE (inf/nan)
without raising, because an uncaught ZeroDivisionError halts the device.
Desktop NilPy keeps ZeroDivisionError. Tracked in
feature-a-esp-math-errors-keep-the-device-running, together with the census of
the other default-halting math paths on ESP.

### NilPy half, implemented 2026-09-24 (frankS)

On ESP, NilPy `//` and `%` by zero give 0, and `/` plus the math domain and
range errors give IEEE inf/nan. This is FRANKUSER'S READING of the owner's
principle quoted above ("we should not halt"); the owner has not ruled on
NilPy specifically. Desktop NilPy keeps CPython's exceptions.

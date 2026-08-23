---
track: A
prio: 60
type: bug
blocked-by: []
status: done
summary: "`a div 0` on plain Integers silently answers -1 on i386/arm32 and 0 on aarch64; only x86-64 raises. EmitDivZeroCheckX64 has no counterpart in ir_codegen_i386/_arm32/_aarch64/_riscv32/_xtensa, so five of six targets let the divide instruction decide -- and every one of them invents a plausible number instead of failing. Pre-existing (reproduces with the pinned binary)."
owner: claude-A
---

# The div-by-zero check is emitted on x86-64 only

Found 2026-08-23 while fixing
[[bug-a-a-variant-div-by-zero-sigfpes-or-answers-garbage]] — the variant ticket
claimed "the plain-Integer path was already right", and writing the test that
asserted it showed the claim holds on x86-64 and nowhere else.

```pascal
uses sysutils;
var ia, ib, ic: Integer;
begin
  ia := 1; ib := 0;
  try ic := ia div ib; writeln('got ', ic)
  except on e: Exception do writeln('raised ', e.ClassName) end;
end.
```

| target | pxx | fpc 3.2.2 |
| --- | --- | --- |
| x86-64 | `raised EDivByZero` | `raised EDivByZero` |
| i386 | **`got -1`** | `raised EDivByZero` |
| arm32 | **`got -1`** | `raised EDivByZero` |
| aarch64 | **`got 0`** | `raised EDivByZero` |

Reproduces identically with `stable_linux_amd64/default/pinned`, so it is
pre-existing, not a regression.

**Silent wrong integer**, and the worst kind: a program that divides by an
unexpected zero gets a number that looks like an answer, keeps running, and
reports something plausible. On x86-64 the same program stops.

## Cause

`EmitDivZeroCheckX64` (`compiler/ir_codegen.inc:2070`) is called from seven
sites in the x86-64 emitter. `grep` finds **no equivalent in any other
backend**:

```
$ grep -c 'EmitDivZeroCheck\|Div0Stub' compiler/ir_codegen_{i386,arm32,aarch64,riscv32,xtensa}.inc
0 0 0 0 0
```

So on those targets the divide instruction decides, and each ISA has its own
opinion — ARM's `sdiv` yields 0, the 32-bit paths come back with -1. The
divergence is diagnostic: it is what "no check" looks like across five ISAs.

The runtime half already exists and is target-independent: `PXXDivZero`
(`builtinheap.pas`) prints `Runtime error 200` and halts, upgraded to a
catchable `EDivByZero` when sysutils installs `PXXDivZeroHook`. Only the
per-backend *pre-divide test* is missing. `--no-div-check` is the existing
opt-out and must keep working.

## Scope, and why it is not five copies of one function

Each backend emits its own divide, so each needs its own two-instruction guard —
but "test the divisor, call PXXDivZero" is one rule, and the x86-64 version
already carries the parts worth sharing (the `--no-div-check` opt-out, the
`FindProc('PXXDivZero')` vs `Div0StubAddr` fallback for unit-free programs, and
the hard error when neither exists). Whoever takes this should lift that
decision into one place and leave only the instruction bytes per backend,
rather than transcribing the whole thing five times —
`devdocs/dev/normalise-dont-special-case.md`, and note the x86-64 copy has a
byte-exact `jnz +5` invariant that will NOT transcribe.

Count the divide sites per backend first: x86-64 has seven, and there is no
reason to assume the others have the same number or the divisor in a
predictable register.

xtensa has no hardware divide at all on some cores — check what it lowers to
before assuming there is an instruction to guard.

## Gate

Track A's, plus `a div 0` and `a mod 0` on plain Integer, Int64, and the
unsigned types raising on x86-64, i386, arm32, aarch64 (and riscv32/xtensa if
they can run at all), a `--no-div-check` row proving the opt-out still opts out,
and a non-zero row per target proving ordinary division is unchanged.

## FIXED 2026-08-23 (claude-A) — five of six backends

`x86-64`, `i386`, `arm32`, `aarch64` and `riscv32` now all raise on integer
`div`/`mod` by zero, matching `fpc 3.2.2 -Mobjfpc -O1` on 18 rows apiece.
**xtensa is deliberately not included** — see the remainder section below.

This implements [[decide-int-div-zero-behavior-unification]], which the user
settled on 2026-07-20 as **option 1, RE 200 everywhere**. The decision was
already made; only the code was missing.

### The measured before-state, which is the argument for the ticket

`1 div 0` and `17 mod 0`, per target, with the pinned binary:

| target | div | mod | why |
| --- | --- | --- | --- |
| x86-64 | raises | raises | had the check |
| i386 | -1 | -17 | no check; whatever `idiv` left behind |
| arm32 | -1 | -1 | no check; ARM `sdiv` does not trap |
| aarch64 | 0 | 0 | ARM spec: zero divisor yields 0 |
| riscv32 | -1 | 17 | RISC-V spec: all-ones quotient, **dividend as remainder** |

Five targets, four different wrong answers, from one source program. riscv32's
`17 mod 0 = 17` is the one worth staring at: it is not an error value, it is a
number a program would happily keep computing with.

### Shape: one policy, five instruction sequences

The ticket asked for the shared part to be lifted rather than transcribed. It
is: **`DivZeroCheckProc`** (`compiler/symtab.inc`, beside `EmitCallProc`)
answers "should a check be emitted, and what does it call" — the
`--no-div-check` opt-out and the `FindProc('PXXDivZero')` lookup, once. Each
backend then contributes only what genuinely cannot be shared:

| backend | helper | divisor | test |
| --- | --- | --- | --- |
| x86-64 | `EmitDivZeroCheckX64` (existing) | rcx | `test rcx,rcx; jnz +5` |
| i386 | `EmitDivZeroCheck386` | ecx / edx:eax | `test ecx,ecx` / `or` of both halves |
| arm32 | `EmitDivZeroCheckArm32` | r1 / r0:r1 | `cmp r1,#0` / `orrs r2,r0,r1` |
| aarch64 | `EmitDivZeroCheckA64` | x1 | `cbnz x1` |
| riscv32 | `EmitDivZeroCheckRV32` | a1 / a0:a1 | `bne a1,zero` / `or t6,a0,a1` |

Each is shaped like that backend's existing `EmitOvfCheck*` twin — same
emit-branch, emit-call, patch-the-offset idiom — so it reads as a sibling of
code already there rather than a new pattern. `EmitCallProc` is already
target-aware, so the call itself needed nothing per-target.

### Two sites per 32-bit target, and the second one is not an instruction

The ticket warned not to assume one divide site per backend, and that was the
right warning in an unexpected direction: on i386, arm32 and riscv32 the
**64-bit** `div`/`mod` is a *software long-division routine*
(`EmitUDivMod64Core_386`, `EmitUDivMod64Arm32`, `EmitUDivMod64RISCV32`), not an
instruction — a 64-iteration loop that with a zero divisor simply runs and
returns nonsense. Each got the guard at its entry, and **one guard per target
covers both signednesses**: the signed core negates the divisor and then calls
the unsigned one, and a zero divisor is still zero after negation.

aarch64 needed only one pair of sites: its `sdiv`/`udiv` are 64-bit and serve
both widths.

### The stub stays x86-64-only, deliberately

x86-64 falls back to an emitted unit-free stub (`Div0StubAddr`) when builtinheap
is absent. That stub is x86-64 machine code. On the cross targets a missing
`PXXDivZero` therefore means **no check** rather than a wrong call — i.e.
today's behaviour for a program that pulls no unit at all. Stated in
`DivZeroCheckProc`'s own comment so the next reader does not treat it as an
oversight.

### Verified

- `test/test_div_by_zero_raises_on_every_target.pas`, wired into `test-core`:
  18 assertions — 10 ordinary-division rows across `Integer` / `Cardinal` /
  `Int64` / `QWord` (the non-zero rows matter: the fix inserts a test in front
  of the hottest arithmetic in the compiler) and 8 raising rows covering both
  widths and both signednesses. `ALL OK` under pxx x86-64, i386, aarch64
  (qemu), arm32 (qemu), riscv32 (qemu) and fpc 3.2.2.
- **`--no-div-check` still opts out on every backend**, restoring each target's
  hardware behaviour exactly (x86-64 SIGFPE, i386/arm32/riscv32 -1, aarch64 0)
  — measured, not assumed.
- Self-host fixedpoint converged in one round; `tools/gate.sh quick` GREEN.
- Doc corrections: `defs.inc`'s `NoDivCheck` comment and
  `pasparser_prog.inc`'s stub comment both said "x86-64 only for now" and now
  say what is actually true.

### Remainder: xtensa

Not done, and not attempted rather than half-attempted. Reasons, in order:

1. **It cannot be run here.** `qemu-xtensa` exists but the bare profile emits an
   ESP image, not a Linux ELF, and the hosted profile needs an ESP-IDF tree.
   Everything above is claimed because it was *executed*; an xtensa arm would be
   claimed because it looked right.
2. **Xtensa branches are 3 bytes with an 8-bit displacement**, and the windowed
   ABI's `call8` rotates the register window. Both are real hazards for a
   branch-over-a-call inserted into the hottest arithmetic path, and neither has
   a local oracle.
3. Its divide is conditional on `XtensaSoftDivide` — hardware `quos`/`rems` on
   some cores, a `__pxx_divsi3` call on others — so it is two more shapes again.

Filed as [[bug-a-the-div-by-zero-check-is-still-missing-on-xtensa]] for whoever
has hardware or a working emulator. Verified that xtensa still compiles
unchanged (`--esp-profile=bare --target=xtensa`).

## Gate

`make compiler/pascal26` converged + the five-target differential +
`--no-div-check` opt-out rows + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-24 — resolved, commit PENDING-COMMIT.

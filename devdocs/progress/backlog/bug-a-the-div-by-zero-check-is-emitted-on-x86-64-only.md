---
track: A
prio: 60
type: bug
blocked-by: []
status: backlog
summary: "`a div 0` on plain Integers silently answers -1 on i386/arm32 and 0 on aarch64; only x86-64 raises. EmitDivZeroCheckX64 has no counterpart in ir_codegen_i386/_arm32/_aarch64/_riscv32/_xtensa, so five of six targets let the divide instruction decide -- and every one of them invents a plausible number instead of failing. Pre-existing (reproduces with the pinned binary)."
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

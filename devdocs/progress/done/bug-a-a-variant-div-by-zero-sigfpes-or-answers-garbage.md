---
track: A
prio: 60
type: bug
blocked-by: []
status: done
owner: claude-A
commit: PENDING-COMMIT
summary: "`v div 0` on Variants had NO pre-divide zero check on any target: x86-64 reached a raw idiv and died on SIGFPE with a core dump (uncatchable, no message), while i386/arm32 answered -1 and aarch64 answered 0 -- silent garbage. The identical program on plain Integers raises EDivByZero correctly, so the check exists and the variant path simply never called it."
---

# A Variant `div` by zero SIGFPEs on x86-64 and answers garbage elsewhere

Found 2026-08-23 by the Variant differential family (`fpc 3.2.2 -Mobjfpc -O1`
vs pxx `1bfd5e9e9`).

```pascal
uses variants, sysutils;
var a, b, c: Variant;
begin
  a := 1; b := 0;
  try c := a div b; writeln(c) except on e: Exception do writeln('raised ', e.ClassName) end;
end.
```

| target | before | fpc |
| --- | --- | --- |
| x86-64 | **SIGFPE, core dumped, exit 136** | `raised EDivByZero` |
| i386 | `-1` | `raised EDivByZero` |
| arm32 | `-1` | `raised EDivByZero` |
| aarch64 | `0` | `raised EDivByZero` |

`mod` behaved the same way. Four targets, three different wrong answers, and the
worst of them is uncatchable: a hardware trap with no message, in a program
whose `except` block was right there.

## The check already existed and the variant path did not call it

The identical program on plain `Integer` variables raises `EDivByZero` and runs
its handler **on x86-64**. So this is not a missing feature — it is one
operator's worth of divide that never reached the guard:

- **x86-64** hand-emits the variant integer ops in `EmitVarBinOp`
  (`compiler/ir_codegen.inc`) and went straight to `cqo; idiv rcx`.
  `EmitDivZeroCheckX64` was already sitting in the same file, already expects the
  divisor **in rcx**, and the variant path already had it there — two
  instructions on the fall-through path next to a ~20-cycle idiv.
- **The other targets** route through `PXXVarBinOp` (`builtinheap.pas`), whose
  two `lVal div rVal` sites had no guard. `PXXDivZero` is declared 300 lines
  above them in the same unit.

That is the whole fix: call the existing check from the two places that skipped
it. Nothing new was written.

## Why the results differed per target

Nothing was checking, so each target's divide instruction did whatever it does
with a zero divisor: x86 `idiv` traps, ARM `sdiv` yields 0, and the 32-bit paths
came back with -1. The divergence is diagnostic, not meaningful — it is what
"no check" looks like across four ISAs.

## Scope

- **Both div/mod arms** in `PXXVarBinOp`: the one reached when either operand is
  VT_DOUBLE (which truncates to integers first) and the pure integer one.
- **Three idiv sites, not one.** The first cut guarded only the pure-integer
  arm and `v(1.5) div v(0.0)` still SIGFPE'd — the VT_DOUBLE arm truncates to
  integers and has its OWN idiv. Found by the test, not by reading; the third
  site is `PXXVarBinOp`'s matching double arm. All three now check.
- **NilPy is untouched and was already correct**: `1 // 0` raises
  `ZeroDivisionError` and is caught, identically under HEAD and the pinned
  binary — its lowering has its own check well before this emitter.
- **How it DIES stays ours**, per CLAUDE.md's strict-flag scope: with sysutils
  present the hook upgrades it to a catchable `EDivByZero` (matching FPC's
  observable behaviour, which is what programs branch on); without sysutils it
  prints `Runtime error 200 (division by zero)` and exits 200 — exactly what a
  plain-Integer divide by zero already does in the same situation.

## Found alongside, and BIGGER than this ticket

The claim "plain Integers were already right" holds on x86-64 and **nowhere
else**. Measured against the PINNED binary, so pre-existing and unrelated to
this change:

```
ia := 1; ib := 0; ic := ia div ib;
  x86-64  raised EDivByZero          i386  got -1
  arm32   got -1                     aarch64  got 0
```

`grep` confirms it: `EmitDivZeroCheckX64` appears seven times in
`ir_codegen.inc` and there is **no equivalent in `ir_codegen_i386.inc`,
`_arm32`, `_aarch64`, `_riscv32` or `_xtensa`**. So ORDINARY integer division by
zero silently answers garbage on five of six targets. Filed as
[[bug-a-the-div-by-zero-check-is-emitted-on-x86-64-only]] at prio 60 — it is a
wider defect than this one and wants its own gate.

This ticket's test therefore does NOT assert plain-Integer div-by-zero: doing so
would pass natively while staying wrong on four targets, which is exactly the
shape of claim this repo keeps getting caught by. That assertion belongs to the
new ticket.

## Verified

`test/test_variant_div_by_zero_raises.pas`, wired into `test-core`: `div` and
`mod` by a zero Variant, by a zero-valued Double variant, and with the zero on a
plain Integer operand; plus non-zero rows proving ordinary division still works
and a plain-Integer row proving that path is unchanged. `ALL OK` under pxx
x86-64, i386, aarch64 (qemu), arm32 (qemu) and fpc 3.2.2.

## Gate

`make compiler/pascal26` converged + the four-target differential + `tools/gate.sh quick`.

## Log
- 2026-08-23 — resolved, commit PENDING-COMMIT.

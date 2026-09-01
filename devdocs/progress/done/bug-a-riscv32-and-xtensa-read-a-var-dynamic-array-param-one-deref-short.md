---
slug: bug-a-riscv32-and-xtensa-read-a-var-dynamic-array-param-one-deref-short
track: A+S
prio: 60
type: bug
status: done
created: 2026-09-02
found-by: frankC
owner: frankC
blocked-by: []
summary: "FIXED 2026-09-02. A dynamic array passed as a `var` parameter was read ONE DEREF SHORT on riscv32 and xtensa: a by-ref frame slot holds &caller_slot and both backends' IR_LEA loaded once, then used the caller's slot as the data pointer. Length(a) and a[1] returned 0 with no crash; writing through it stored into the caller's STACK and left the caller's array untouched. arm32/x86-64/i386/aarch64 were all correct, and VALUE and CONST params were correct everywhere — so any test written in those modes passes on the broken backends. examples/sat/satdemo.pas and examples/fm/fm.pas both crashed on a later read."
---

# riscv32 and xtensa read a `var` dynamic-array parameter one deref short

Found by compiling `examples/` across five backends against the x86-64 oracle
(`umbrella-cross-target-codegen-is-correct`, 2026-09-02) — not by triage. Two
programs crashed on exactly two targets:

```
fm      | i386:BUILD arm32:ok riscv32:RUN(139) aarch64:ok xtensa:RUN(139)
satdemo | i386:ok    arm32:ok riscv32:RUN(139) aarch64:ok xtensa:RUN(135)
```

## The minimal shape

```pascal
type TIntArray = array of Integer;
procedure ReadVar(var a: TIntArray);
begin WriteLn(Length(a), ' ', a[1]); end;
var m: TIntArray;
begin SetLength(m, 4); m[1] := 99; ReadVar(m); end.
```

| target | `Length(a)` | `a[1]` |
| --- | ---: | ---: |
| x86-64, i386, arm32, aarch64 | 4 | 99 |
| **riscv32** | **0** | **0** |
| **xtensa** | **0** | **0** |

A **value** or **const** parameter of the same type is correct on every target.

## Cause

`EmitSlotAddr*` puts the frame slot's address in the result register, then:

```pascal
if (Syms[si].IsArray and (Syms[si].ArrLen = -1)) or ... then
  rv32_lw(reg_a0, reg_a0, 0)      { slot -> handle }
```

For a **by-ref** param the frame slot holds `&caller_slot`, so that single load
yields the caller's SLOT ADDRESS and the code then uses it as the data pointer.
One more deref is needed. arm32 has carried both loads since it was written and
says so plainly — *"load it (needed either way — SetLength wants to publish
through it, Length/indexing want to deref it once more)"*. riscv32 and xtensa
each had one.

Note riscv32/xtensa deliberately do NOT gate this on `InLValueWrite` the way
arm32 does (their indexed writes arrive here needing the data pointer, and
SetLength takes the slot address from a separate routine), so the fix is an
unconditional second load for the by-ref dynamic-array case rather than a copy
of arm32's gate.

## Why nothing caught it, which is the reusable part

1. **It is a READ bug before it is a write bug.** `Length(a)` returning 0 does
   not crash, does not warn, and looks like an empty array — a plausible value.
2. **The correct parameter modes are the common ones.** VALUE and CONST params
   were right on every target, because those slots genuinely hold the handle. A
   test written with either mode passes on the broken backends. The regression
   test therefore keeps value and const rows beside the var rows *as controls*.
3. **The write corrupted somewhere else entirely.** `a[3] := 21` stored through
   the caller's slot address as if it were the data pointer — into the caller's
   stack — while leaving the caller's array untouched. Both example programs
   died on a subsequent read, nowhere near the store that did the damage.

Pre-fix riscv32 also printed `a[1] = 134780736`: a raw address surfacing as an
ordinary integer, which is the right-length/wrong-content class
`debugging-playbook.md` gained a section on the same day (frankA, `a16c02762`).

## The fix, and the control in both directions

Second load added to `ir_codegen_riscv32.inc` and `ir_codegen_xtensa.inc`.

`test/test_dynarray_var_param.pas`, new, wired on six targets. Verified with the
revert asserted by grep (0 fix-notes present, not assumed):

- **pre-fix: x86-64, i386, arm32 and aarch64 PASS.** They were already correct,
  so a test that failed there too would have been testing something else.
- **pre-fix: riscv32 and xtensa FAIL** — `var param High = -1, want 3`,
  `var param a[1] = 134780736, want 99`, and xtensa reaches SIGBUS.

After the fix all six pass, and `satdemo` and `fm` both go green on riscv32 and
xtensa (`fm` still fails to BUILD on i386 for an unrelated reason —
`lib/rtl/image.pas` passes a record by value and i386 refuses that).

## Landed

`eabd599ee` — the fix, the test and its six wirings in one commit.

## Measured at

compiler `58620a6d3662`, `converged after 1 round(s)`, `gate.sh quick` GREEN with
the FPC seed canary PASS.

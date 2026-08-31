---
slug: bug-a-an-int64-multiply-dies-with-an-illegal-instruction-on-xtensa
track: A
prio: 25
type: bug
status: rejected
found: 2026-08-31
found-by: frankA
owner: ""
blocked-by: []
summary: "REJECTED 2026-08-31, the same day I filed it: NOT A DEFECT. Both SIGILLs are one documented qemu limitation with an existing flag -- no qemu-xtensa core implements MUL32HIGH (measured across all 8 cores, before either of us arrived), so ANY 64-bit multiply dies, and integer formatting strength-reduces div-by-10 into one, which is why `WriteLn(i)` died too. `--xtensa-soft-mulhigh` makes both pass; I verified that on the PINNED compiler with only the flag varying. tools/run_target.sh:95 has carried the explanation all along. Real xtensa hardware has the instruction. The cost of filing this was not the ticket -- it is that I REMOVED A WORKING xtensa codegen arm because it produced this signal, and had to restore it. What the ticket got right is the one thing worth keeping: it refused to label the cause codegen-vs-core, and named what would settle it, so nothing false was published. Any verdict produced under the flag must SAY so -- run_target.sh notes the emulator is not bit-identical to hardware for multiplies under it."
---

# An Int64 multiply dies with an illegal instruction on xtensa — REJECTED, it is the emulator

## Why this is rejected (2026-08-31, found by frankS, verified here)

`--xtensa-soft-mulhigh`. Same source, PINNED compiler, only the flag varying:

```
  <no flag>              start int-ok i64-add-ok i64-sub-ok  SIGILL
  --xtensa-soft-mulhigh  start int-ok i64-add-ok i64-sub-ok i64-mul2-ok i64-mul-ok end
```

`tools/run_target.sh:95` documents it: no qemu-xtensa core implements
MUL32HIGH -- all 8 measured -- and integer formatting strength-reduces div-by-10
into a 64-bit multiply, which is why numeric output SIGILLs by the same
mechanism. My "four cores fail identically" was right and understated.

**The real cost of this ticket:** the signal made me pull a *working* xtensa
in-place-append arm from `ir_codegen_xtensa.inc`, on the theory that my a2/a3
register handling was wrong. It was not. Rebuilt and run with the flag, that arm
gives 16 allocations for 20000 appends where the concat path gave 19780, with
every correctness check passing. Restored.

**The lesson, which is not "check for a flag":** every xtensa probe I wrote
crashed at its own output, so the newest thing I had changed always looked
guilty. A broken *reporting channel* blames the thing under test. Running the
baseline is what should have caught it, and did -- I noticed the pinned compiler
died identically -- but I read that as "xtensa is broken here" rather than
"my instrument is".

## Original report follows



## Repro — five lines

```pascal
program xt9;
var a, b: Int64;
begin
  WriteLn('before');
  a := 7; b := a * 2;
  if b = 14 then WriteLn('after-ok') else WriteLn('after-BAD');
end.
```

`pascal26 --target=xtensa --platform=posix xt9.pas xt9 && qemu-xtensa xt9`
prints `before`, then `qemu: uncaught target signal 4 (Illegal instruction)`.

## What is and is not affected

Reporting only through **string literals**, because `WriteLn` of an integer is
itself broken here and confounded three earlier probes of mine before I noticed:

| | xtensa | x86_64 | arm32 | riscv32 |
| --- | --- | --- | --- | --- |
| Int64 `a + a` | ok | ok | ok | ok |
| Int64 `a - 2` | ok | ok | ok | ok |
| Int64 `a * 2` | **SIGILL** | ok | ok | ok |
| Int64 `a * a` | not reached | ok | ok | ok |
| `WriteLn(i)`, i: Integer | **SIGILL** | ok | ok | ok |

Both on the PINNED compiler as well as HEAD, so neither is new. They are very
likely ONE defect: printing an integer extracts digits with div/mod, and xtensa
already carries `__pxx_udivsi3`/`__pxx_divsi3` for cores without hardware divide
(`--xtensa-cpu=lx6`), so a missing or mis-selected mul/div path would explain
both. **That is a hypothesis, not a finding.**

Not everything is broken -- a 20000-iteration `s := s + 'x'` loop and a
20000-iteration `SetLength` loop both run and produce correct results on xtensa,
verified by comparing lengths and characters rather than printing them.

## The open question, named rather than guessed

Is this **our codegen** or the **emulated core**? Same binary against four qemu
cores -- `dc232b`, `dc233c`, `de212`, `lx106` -- fails identically at the same
point. That argues against a single bad core choice but not against all four
lacking the option. Settling it needs one of:

- the faulting **instruction** (dump the guest core's PC and decode the bytes;
  `qemu-xtensa` writes a core under `ulimit -c unlimited`), or
- a run on real **S2/S3 hardware**, which is Track S and the user's board.

Do not "fix" this by changing the multiply to something else until that is
answered -- a workaround before the diagnosis is how a core-option mismatch gets
recorded permanently as a codegen bug.

## How it was found

`PXXStrSetLen`'s new geometric growth wrote `want * 2` and was the first Int64
multiply on this path; xtensa began dying on `SetLength`. It now doubles by
addition, with a comment pointing here. That is a deliberate, tracked sidestep
and the two forms are exactly equal, so restoring the multiply costs nothing
once this is understood.

---
slug: bug-a-an-int64-multiply-dies-with-an-illegal-instruction-on-xtensa
track: A
prio: 60
type: bug
status: backlog
found: 2026-08-31
found-by: frankA
owner: ""
blocked-by: []
summary: "`b := a * 2` with a, b: Int64 dies with SIGILL on xtensa; Int64 add and subtract are correct and every other target is correct. So does `WriteLn(i)` for a plain Integer, which is very likely the same root cause (digit extraction is div/mod). Both reproduce on the PINNED compiler, so neither is a regression -- they were found because a runtime change became the first code in builtinheap.pas to use an Int64 multiply. NOT YET ESTABLISHED, and the ticket deliberately does not claim it: whether this is our codegen or the EMULATED CORE lacking the mul/div option. Four qemu cores (dc232b, dc233c, de212, lx106) fail identically, which weakens the core-config theory but does not kill it -- they may share the gap. What settles it is naming the faulting instruction, or running on real S2/S3 hardware."
---

# An Int64 multiply dies with an illegal instruction on xtensa

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

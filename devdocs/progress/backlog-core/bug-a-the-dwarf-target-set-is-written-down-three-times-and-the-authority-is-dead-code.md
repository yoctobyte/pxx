---
track: A
prio: 30
type: bug
status: open
found: 2026-08-30
found-by: frank-optimize-b4
summary: "DbgArchSupported states the DWARF Tier-1 target set correctly and is NEVER CALLED. The live gate is duplicated across three doDebug assignments in two ELF writers, and three comments said x86-64 only. Comments fixed; the duplication and the dead authority are not. Measured: -g emits debug sections on all four targets."
---

# The DWARF target set is written down three times, and the only correct statement is dead code

Found by `tools/docaudit.py targets` (frankD's derive-don't-match audit) over
`compiler/**`, from a `elfwriter.inc` hit whose comment sat **one line** above a
condition contradicting it.

## What is true, measured rather than read

`-g` emits 4 `.debug` sections on **x86-64, aarch64, i386 and arm32**; xtensa and
riscv32 are excluded. Verified by compiling the same program for each target and
counting sections with `readelf -S`.

## The three places it is written, and why reading any one of them misleads

| where | says | live? |
| --- | --- | --- |
| `DbgArchSupported` (`elfwriter.inc`) | the correct four | **never called — zero call sites** |
| `doDebug` in the two 64-bit writers | `x86_64 or aarch64` | live |
| `doDebug` in the 32-bit writer | `i386 or arm32` | live |

Three comments additionally asserted **"x86-64 only"** (`elfwriter.inc` x2,
`compiler.pas`'s `-g` arm). Those are **fixed** — comment-only, self-host
byte-identical, `7c4f7ce26297`.

**The trap is worth stating because it caught me.** Reading the condition
directly under the corrected comment gives the answer "two targets", and that is
a *reasoned* answer from real code that is still wrong — the second writer is
190 lines away. Only compiling for all four gave "four". The near-miss is the
finding: this is the shape where measuring beats reading even when you are
reading the implementation itself.

## What is NOT fixed, and why it needs care rather than a quick edit

The obvious fix is to make the dead authority live: `doDebug := DebugInfo and
DbgArchSupported` at all three sites, collapsing three duplicated target lists
into one. It is *probably* behaviour-preserving, because each writer only ever
runs for its own target family — but that binding was not proved, and the
writers also serve exec / shared / `--emit-obj` modes that this ticket did not
exercise. A change that is "probably equivalent" to a gate on debug-info
emission is exactly the kind this repo asks you to prove rather than assume.

So: **three lists, one dead authority, and a fix that is one line per site once
someone proves the writer/target binding.** Do that with a measurement across
every target x every output mode, not by reading the dispatch.

## Why it is a bug ticket and not an audit note

A function whose only content is a correct statement, that nothing calls, is
worse than no function: it reads as the authority. Anyone grepping
`DbgArchSupported` finds the right answer and reasonably concludes it is
enforced. That is a false statement about a gate, told at the point of maximum
authority — the same class as
`bug-a-threadsafe-is-x86-64-only-is-asserted-in-five-places-and-has-been-false-since-july`,
and this one has an extra twist: **the correct sentence is the dead one.**

## Gate

The comment half is done and byte-identical. The code half: `make
compiler/pascal26` plus `-g` emitting the same section count on all four
supported targets and none on xtensa/riscv32, across exec and shared output.

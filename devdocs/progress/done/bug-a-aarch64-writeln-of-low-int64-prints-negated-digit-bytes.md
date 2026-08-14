---
track: A
prio: 45
type: bug
blocked-by: []
summary: "On aarch64 ONLY, WriteLn(Low(Int64)) prints -'..--).0-*(+,))+(0( instead of -9223372036854775808. Every one of the 19 digit bytes is Ord('0') - d where it should be Ord('0') + d, so the value is right and the rendering is wrong. Low(Int64)+1 prints correctly, and x86-64 / i386 / arm32 all print correctly. Silent output corruption in the integer writer, reachable from any program that prints Low(Int64)."
status: done
owner: agent-AN
---

# aarch64: `WriteLn(Low(Int64))` prints negated digit bytes

- **Type:** bug (silent wrong output, one target) — **Track A** (the integer
  writer lives in `compiler/builtin/builtin.pas`; the divergence is per-backend,
  so it is codegen).
- **Filed by Track B** on 2026-08-14, found during the per-backend sweep
  [[bug-a-trunc-and-round-of-an-out-of-range-double-return-int64-min-silently]]
  asked for. Not a float bug — `Trunc` was only how the value arrived.

## Repro — no float involved

```pascal
program imin;
var a, b: Int64;
begin
  a := -9223372036854775807; a := a - 1;   { Low(Int64), built at runtime }
  WriteLn('runtime_low=', a);
  b := Low(Int64);
  WriteLn('const_low=',   b);
  b := High(Int64);
  WriteLn('const_high=',  b);
end.
```

| target | `runtime_low` | `const_low` | `const_high` |
| --- | --- | --- | --- |
| x86-64 | -9223372036854775808 | -9223372036854775808 | ok |
| i386 | -9223372036854775808 | -9223372036854775808 | ok |
| arm32 | -9223372036854775808 | -9223372036854775808 | ok |
| **aarch64** | **-'..--).0-*(+,))+(0(** | **-'..--).0-*(+,))+(0(** | ok |

Built with the pinned stable; aarch64 run under `qemu-aarch64-static`. Pure
computation and formatting, no syscalls or threads, so qemu is a faithful host
here (unlike the network/thread cases `tools/lib_cross_sweep.sh` warns about).

## The bytes decode exactly — this is a sign, not corruption

Byte by byte against the expected digits:

```
expected:  9   2   2   3   3   7   2   0   3   6   8   5   4   7   7   5   8   0   8
got:       '   .   .   -   -   )   .   0   -   *   (   +   ,   )   )   +   (   0   (
hex:      27  2E  2E  2D  2D  29  2E  30  2D  2A  28  2B  2C  29  29  2B  28  30  28
0x30-hex:  9   2   2   3   3   7   2   0   3   6   8   5   4   7   7   5   8   0   8
```

Every byte is `Ord('0') - d`. **All nineteen**, including the one the writer
peels separately — not just the first. So the digits themselves are computed
correctly and the character formed from each has the wrong sign.

## What is NOT the cause — already ruled out by measurement

- **Not `div`/`mod` sign.** `-7 div 10`, `-7 mod 10`, `Low(Int64) div 10` and
  `Low(Int64) mod 10` were checked on all four targets and against FPC 3.2.2:
  all agree (`0`, `-7`, `-922337203685477580`, `-8`). Pascal truncation toward
  zero is intact on aarch64.
- **Not the peel logic in `IntToStrPadded`.** Its `Low(Int64)` comment
  (`compiler/builtin/builtin.pas` ~line 940) describes the right algorithm, and
  three of four targets execute it correctly.
- **Not `Chr`/`Ord` in general.** In a plain program on aarch64,
  `d := -(a mod 10)` gives `8` and `Chr(Ord('0') + d)` gives `'8'` — correct.
  It only goes wrong inside the writer.
- **Not "any negative Int64".** `-7`, `-12345` and `Low(Int64)+1` all print
  correctly on aarch64. Only the exact minimum fails — and note `Low+1` and
  `Low` take the *same* path and leave the loop with the *same* quotient, which
  is what makes this odd and worth an actual look at the emitted code rather
  than another guess.

## Why it matters more than an edge case

`Low(Int64)` is not exotic here: it is what a saturating or indefinite float→int
conversion produces (that is how this was found), what an overflowing negation
lands on, and a common sentinel. The failure is **silent** — no crash, no
diagnostic, just a line of text that is not a number, on one target only, which
is the shape that survives a green gate.

## It is `WriteLn`'s writer specifically — `IntToStr` and `Str` are fine

The best narrowing available, same binary, same value, aarch64:

```pascal
a := -9223372036854775807; a := a - 1;
WriteLn('writeln  =', a);            { -'..--).0-*(+,))+(0(   WRONG }
WriteLn('inttostr =', IntToStr(a));  { -9223372036854775808   ok    }
Str(a, s);
WriteLn('str      =', s);            { -9223372036854775808   ok    }
```

So `lib/rtl/sysutils`'s `IntToStr` and `Str` both render `Low(Int64)` correctly
on aarch64 — **only the writer `WriteLn` reaches for its own integer argument
is wrong.** Two renderers, one of them broken on one target, is the
two-mechanisms-for-one-concept smell in
`devdocs/dev/normalise-dont-special-case.md`; the fix may well be to route
`WriteLn` through the one that works rather than to repair the second path.

**Reproduces identically at `-O0` and `-O2`**, so it is not an optimizer pass.

## Where to look

The integer path `WriteLn` lowers to, compiled for aarch64 — start from
`compiler/builtin/builtin.pas` `IntToStrPadded` and whatever the write
lowering actually calls (confirm which, do not assume: `PXXDBG=a.ir:<proc>`,
`a.ast:<proc>`, and `-g -O2` + gdb per `devdocs/dev/debugging-playbook.md`).
Compare against **arm32**, which is correct and shares the `div`/`mod` shape —
that pair is the cheapest diff available.

## Gate

The table above reads `-9223372036854775808` on all four targets, plus the same
for `IntToStr(Low(Int64))` and `Str(Low(Int64), s)`, `make test` + self-host
fixedpoint, and cross.

## Resolution

One instruction, in two places. The ticket's narrowing was right down to the
last line — including "compare against arm32, which is correct and shares the
div/mod shape; that pair is the cheapest diff available." It was. arm32's digit
loop says `udiv` and carries the comment *"divides the non-negative
magnitude"*; aarch64's said `sdiv`. aarch64 was the outlier.

### Why sdiv is wrong there at all

`EmitwriteIntA64` handles the sign first — emit `-`, then `neg x0, x0` — so by
the digit loop `x0` is a MAGNITUDE, and unsigned division is what a magnitude
wants. Signed division happened to agree for every value except one:

**`neg` of `Low(Int64)` is `Low(Int64)`.** Its magnitude, 9223372036854775808,
does not fit a signed 64-bit register, so `x0` stayed negative. Every `msub`
remainder then came out negative and `add x5, x5, #48` produced `Ord('0') - d`
— which is exactly the byte table in the report, all nineteen digits. Read as
unsigned, the very same bit pattern IS the correct magnitude, so `udiv` needs
no special case for it.

That also answers the ticket's "what makes this odd": `Low+1` and `Low` do take
the same path and leave the loop with the same quotient. The difference is
entirely in the operand `neg` produced.

### The sibling site the repro could not reach

`EmitwriteIntWA64` — the FIELD-WIDTH variant — had the identical `sdiv` in its
identical digit loop. The repro used no width, so the ticket found one site and
there were two. Both fixed. (`devdocs/dev/normalise-dont-special-case.md`: grep
for the sibling before closing.)

### Confirmed against every backend

`test/test_cross_int64.pas` extended with `Low(Int64)` built at run time and as
a constant, `High(Int64)`, and `Low+1` — then run on all five targets:
**x86-64, aarch64, arm32, riscv32 and i386 now produce byte-identical output.**
The test was wired for arm32 and riscv32 only; it is now wired for **aarch64**
too, as a differential against the x86-64 oracle, so this cannot regress
silently again.

`IntToStr` and `Str` were already correct and are untouched — the ticket's
suggestion to route WriteLn through them was not needed once the actual
divergence turned out to be one opcode rather than an algorithm.

### A separate bug this surfaced

With aarch64 fixed, the same sweep showed **i386 and arm32 ignore the field
width entirely when writing an Int64** (`a:12` prints unpadded), while a 32-bit
`Integer` with the same width pads correctly on those very targets, and FPC
pads both. Different targets, different mechanism, not caused by this change —
filed as
[[bug-a-32bit-targets-ignore-the-field-width-writing-an-int64]] rather than
folded in. It is deliberately NOT covered by the extended test above, which
would otherwise go red on two targets for someone else's defect.

Gate: `gate.sh quick` GREEN (self-host fixedpoint + `--tier quick` + FPC seed
canary), plus the five-target differential above. `compiler/emit.inc` is
compiler code, not a frozen builtin, so no re-pin.

## Log
- 2026-08-15 — resolved, commit fb74050e5.

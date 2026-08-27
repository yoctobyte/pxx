---
slug: bug-a-xtensa-pc-relative-encoders-silently-truncate-an-out-of-range-offset
track: A+S
prio: 60
type: bug
blocked-by: []
status: done
owner: agent-A
summary: "Every PC-relative field in xtensaenc.inc ended in `and $3FFFF` / `and $FF` with no range check, so an offset past the field silently wrapped and the instruction targeted a different, valid address. An esp32s3 IDF image jumped 2^18 bytes short, landed mid-instruction, and died as IllegalInstruction three functions from the cause. Fixed: one signed-range guard at all four encoders."
---

# xtensa PC-relative encoders silently truncate an out-of-range offset

**A mask is not a check.** All four PC-relative encoders in `xtensaenc.inc`
ended by masking the offset into its field:

| encoder | field | reach | had a check |
| --- | --- | --- | --- |
| `EncodeXtensaJ` | imm18, bytes | ±128 KiB | no |
| `EncodeXtensaCall0` | imm18, words | ±512 KiB | no |
| `EncodeXtensaCall8` | imm18, words | ±512 KiB | no |
| `EncodeXtensaBranch` | imm8, bytes | −128..+127 | no |

The whole file contained **zero** calls to `Error`. Past the field, the offset
wraps and the instruction targets a *different, perfectly valid* address. No
fault at encode time, none at link time — the program simply jumps somewhere
else.

## How it presented

An ESP-IDF `--platform=esp --target=xtensa --xtensa-abi=windowed` esp32s3 image:

```
Guru Meditation Error: Core  0 panic'ed (IllegalInstruction). Exception was unhandled.
PC      : 0x4200ca51
Backtrace: 0x4200ca4e:0x3fca4b60 0x42005ceb:0x3fca4c80 0x4204e8aa:0x3fca4cb0
```

The entry stub is three instructions:

```
4200c88c <app_main>:
4200c88c:  entry  a1, 0x120
4200c88f:  or     a7, a1, a1
4200c892:  j      4200ca4b        <-- mid-instruction, inside sShiftRightSticky
```

`0x4200ca4f` is a 3-byte `sub a3, a3, a9`, so `0x4200ca4b` desynchronises the
stream: decode 3 bytes to `0x4200ca4e`, 3 more to `0x4200ca51`, illegal opcode.
That is exactly the reported PC and backtrace.

## The arithmetic, which is the whole proof

The main body sat at code offset **262591**. The encoder computes
`(offset - 4)` = **262581** and masks it:

```
262581 mod 262144 (2^18) = 437
```

so the `j` encoded 437 bytes forward. Intended target `0x4204ca4b`; actual
`0x4200ca4b`. **They differ by exactly `0x40000` = 2^18** — one dropped bit of
the masked field, and nothing anywhere said so.

## Why it stayed hidden

xtensa images were small. Bare-metal is SRAM-bounded at tens of KB, and under
IDF xtensa was (wrongly) treated as bare and pulled no RTL, so its images were
~47 KB. Nothing on this target had ever needed to jump more than 128 KB.
[[feature-a-complete-the-builtin-unit-on-the-esp-class-targets]] is what first
produced a large xtensa image, and this fired immediately.

The cost was in the *silence*, not the wrap: the offset was nowhere near the
boundary in the error message, because there was no error message. Nothing
pointed at the encoder. It took a disassembly of the entry stub and the
arithmetic `262591 - 262144 = 437` to name it — the "plausible wrong value far
from the cause" shape `devdocs/dev/debugging-playbook.md` opens with.

## The fix

One `XtensaRelCheck(v, lo, hi, what)` guard, used at all four sites — the
`normalise-dont-special-case` shape: one range-check routine, four call sites,
rather than four hand-written comparisons that can drift.

It checks the **signed** range, deliberately, rather than "did the mask change
the value": masking IS correct for negative offsets (two's complement is what
the field wants), and the naive test would reject every backward branch.

`EncodeXtensaCall0/Call8` additionally assert the target is 4-aligned — they
encode a *word* offset via `div 4`, so a stray byte is silently truncated away
by the division, a second silent-wrong-target hiding in the same routine.

The same program now says:

```
error: target xtensa: j displacement 262581 is outside the encodable range
       -131072..131071; the code is too large for this branch form
```

## What this does NOT fix

The image still cannot be built — it now fails loudly instead of crashing on
chip. Making it *work* needs a reach-independent entry jump and is
[[bug-a-xtensa-entry-jump-cannot-reach-a-main-body-past-128kb]].

## Gate

`make compiler/pascal26` (self-host fixedpoint), the bare-float build rows on
all four ESP spellings byte-identical per pair, and the bare execution rows on
**both** real emulators:

```
bare-float esp32c3  == x86-64 oracle
bare-float esp32s3  == x86-64 oracle
esp32c3 IDF esp_timer callback ok
```

Nothing that fits its field changed encoding: no existing image moved.

## Log
- 2026-08-27 — resolved, commit f4301e3de.

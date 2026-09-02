---
type: bug
track: A
prio: 85
status: open
summary: Under -dPXX_SHORTSTRING, `s := s + 'cd'` on a plain string[10] segfaults on
  x86-64 and is correct on i386, arm32, aarch64 and riscv32.
---

# String concat segfaults on x86-64 under the byte-prefix mode

**This blocks the phase-4 flip**, and it is more fundamental than
`bug-a-an-array-of-shortstrings-is-corrupt-under-the-byte-prefix-mode`: no array,
no record, no pointer, no index. Six lines.

## Repro

```pascal
program cc;
var s: string[10];
begin
  s := 'ab';
  WriteLn('before len=', Length(s), ' [', s, ']');
  s := s + 'cd';
  WriteLn('after  len=', Length(s), ' [', s, ']');
end.
```

Measured at `e7a9dfa4b`, compiler sha `a81084690bac`.

| target | default | `-dPXX_SHORTSTRING` |
| --- | --- | --- |
| **x86-64** | `after len=4 [abcd]` | **SIGSEGV (139) after printing `before`** |
| i386 | `[abcd]` | `[abcd]` |
| arm32 | `[abcd]` | `[abcd]` |
| aarch64 | `[abcd]` | `[abcd]` |
| riscv32 | `[abcd]` | `[abcd]` |

**x86-64 is the ONLY broken target**, which is the inverse of the usual shape
here — and it is the default target, the one the dev loop builds, the one
`gate.sh quick` runs and the one the flip meets first.

`-O` invariant: SIGSEGV at both `-O0` and `-O2`, so this is a codegen arm rather
than an optimiser predicate.

`before` prints correctly (`len=2 [ab]`), so the crash is in the concat itself,
not in the preceding store or in `WriteLn`.

## A second symptom of what is probably the same fault

In a longer program the same statement instead died with
`pxx: out of memory (heap arena mmap failed)`, exit **203**, rather than
SIGSEGV. A corrupted length driving an allocation would explain both — a wild
size to `mmap` in one path, a wild write in the other — but **nobody has read
the emitted code, so that is where to point gdb and not a diagnosis.**

## Why a suite would not have caught it

Concat is exercised constantly, but **only in the default mode**; nothing sweeps
`-dPXX_SHORTSTRING`. The overhaul's own repros are string *comparison* and
*indexing*, so the most common string operation in Pascal was never in the
population. This was found by sweeping constructs under both modes and diffing,
which is the thing that had not been done.

## LOCATED — the two arms, and a tyShortString matches NEITHER (frankB, 2026-09-02)

**Not the inline frozen-concat arm, which is the obvious suspect and is not on
this path.** I widened its operand loads first; the crash address did not move
by a single byte, and that edit is REVERTED rather than landed — it repaired a
real width bug in an arm this program never enters, which is a microfix wearing
the shape of a fix.

**The path is the MANAGED concat**, `ir_codegen.inc`, the arm that prepares each
operand for `PXXStrConcat`. Both operand preparations key on a bare equality:

```
if      rhsTk = tyAnsiString  then ... read [rdx-8]
else if rhsTk = tyString      then   mov rcx,[rdx] ; add rdx,8
else                                 lea rdx,[rsp] ; mov ecx,1     <- a CHAR
```

and the identical shape for `lhsTk` twenty lines below. **A `tyShortString`
operand matches neither test and falls into the `else`, which is the BARE CHAR
arm** — so a whole string is concatenated as one character, with `rdx` pointing
at a stack slot rather than at string data. `lhsTk`/`rhsTk` come from
`IntToTypeKind(IRTk[..])`, which tags a frozen operand generically.

**The fix is the same one this feature has taken four times tonight:**
`lhsTk := IRStrTkOf(left)` / `rhsTk := IRStrTkOf(right)`, then
`TypeIsFrozenString(..)` for the branch and `FrozenStrPrefixSize(..)` for the
length load and the `add`. Byte width needs `movzx rcx, byte [rdx]`
(`48 0F B6 0A`) and `movzx rdi, byte [rsi]` (`48 0F B6 3E`) in place of the
`mov` forms. **I did not land it** — three attempts to apply it cleanly failed
on text matching at the hour I was working, and an unverified hand-assembled
edit in the concat hot path is worse than an accurate handover.

**Evidence, so the next session does not re-derive it:**
- `rdx = $626102` at the fault — the length byte 2 followed by `ab`, i.e. a
  byte-prefixed string read as a wide word.
- The crash is in BUILTIN code (`0x401d14`, no symbol, broken backtrace), not
  in the program body, which is what says the inline arm is not involved.
- **Conversions are all fine and rule themselves out**: frozen→managed,
  frozen→frozen and managed→frozen each round-trip correctly under the flag
  (`f2m [ab] 2`, `f2f [xy]`, `m2f [pq]`). Only the concat fails.
- `m := s + 'cd'` — result assigned to a MANAGED string — crashes too, which is
  the direct evidence for the managed arm rather than the frozen one.
- x86-64 only, because it is the only backend that inlines this; the others call
  `PXXStrConcat` with lengths rather than reading them.
- -O invariant, so `CmpFusible`'s "-O0 correct, -O1+ wrong" tell correctly does
  not fire.

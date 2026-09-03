---
type: bug
track: A
prio: 85
status: done
summary: Under -dPXX_SHORTSTRING, `s := s + 'cd'` on a plain string[10] segfaults on
  x86-64 and is correct on i386, arm32, aarch64 and riscv32.
owner: frankB
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

## FIXED — the substitution, in THREE arms, not one (frankB, 2026-09-03)

The located arm was right and it was not alone. All three are in
`compiler/ir_codegen.inc`, all three are x86-64-only, and all three keyed on a
bare `= tyString` while the IR tags every frozen operand tyString generically.
Each now asks `IRStrTkOf` for the operand kind, `TypeIsFrozenString` for the
branch and `FrozenStrPrefixSize` for the length load and the pointer bump
(`movzx r64, byte [m]` at width 1).

1. **The managed concat arm** (`IREmitNode`, the `IRTk[node] = tyAnsiString`
   `tkPlus` arm) — the diagnosed one. A tyShortString matched neither test and
   took the bare CHAR `else`. **This is the SIGSEGV.**
2. **`EmitAnsiStrAppendToSym`** and its gate `IRIsSelfStrAppend` — the in-place
   append behind `m := m + s`. Here the generic tyString tag DID match, so the
   arm read eight bytes of `[len][chars]` as a length: **this is the
   `out of memory (heap arena mmap failed)` symptom** recorded above, not a
   second guess at the same one. Fixing (1) alone left this live and the two
   fail differently, which is why the OOM shape existed at all.
3. **The inline frozen-concat arm** (`IRTk[node] = tyString`, the 272-byte
   stack temp). **My predecessor's revert was right about the path and wrong
   about reachability, and that is worth recording:** it is unreachable from
   the repro *and* from `{$H-}`, but `-uPXX_MANAGED_STRING -dPXX_SHORTSTRING`
   reaches it — bare `string` frozen AND `string[N]` byte-prefixed — and
   `u := s + t` over three `string[10]`s segfaults there. Verified by the
   `sub rsp,272` byte pattern being present in the emitted binary in that
   corner and absent in the others. The temp KEEPS its 8-byte prefix: the
   result is an IR_BINOP node tagged tyString and `IRFrozenKindOfAddr` answers
   tyString for it, so every downstream reader expects 8. Only the operand
   reads follow the operand's own width.

**Test: `test/test_shortstring_concat.pas`, wired four ways** (default /
`-dPXX_SHORTSTRING` / `-uPXX_MANAGED_STRING` / both) in `test-core`, same
expected text in all four.

**Positive control, measured, not assumed.** Fix reverted → compiler
`7f95d3b1c5c2` → the two `-dPXX_SHORTSTRING` rows SIGSEGV with no output and
the two default rows are unchanged. Restored → `6a01584e19b4`, byte-identical
to the pre-control build, so the revert cycle drifted no seed.
**THE PINNED COMPILER PASSES ALL FOUR ROWS AND IS USELESS AS A CONTROL HERE:**
it predates the byte-prefix layout, so `-dPXX_SHORTSTRING` is a no-op in it —
`test_shortstring_byte_prefix` prints the wide layout row `5 0 0 0 0 0` under
the flag. A green that is correct about a different compiler.

**Both modes, five targets, 11 rows, all identical and correct:** x86-64, i386,
arm32, aarch64 (riscv32 refuses the `-u` corner at compile time with a loud
`frozen tyString concat unsupported`, mode-invariantly — pre-existing, not
this). `tools/gate.sh quick` GREEN with the FPC seed canary run, not skipped.

**Found on the way and NOT this bug** (mode-invariant on the byte-prefix axis,
identical under the pin):
`bug-a-a-one-char-string-literal-in-a-frozen-concat-folds-to-integer-addition`.

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

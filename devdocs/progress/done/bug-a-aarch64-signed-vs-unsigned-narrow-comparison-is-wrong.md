---
summary: "aarch64 only: comparing a signed Integer/int against a narrow UNSIGNED value (Byte/Word, unsigned char/short, and plain char) gives the wrong answer — `-1 < Byte(1)` is FALSE. Silent, both frontends, every -O level"
type: bug
track: A
prio: 85
owner: claude-b-night2
---

# aarch64: `signed < unsigned-narrow` compares as unsigned

- **Type:** bug — Track A (aarch64 backend / comparison lowering)
- **Status:** done
- **Opened:** 2026-08-05
- **Found by:** `tools/gcc_diff_probe.sh --target aarch64`, new
  integer-promotion case batch.
- **Measured at:** HEAD `45e0a6bd4` (self-hosted `compiler/pascal26`), and
  reproduced identically with the **pinned stable** (`stable_linux_amd64/default`,
  VERSION 243) — so this is not a fresh regression in an unpinned tree.

## Repro — Pascal

```pascal
program pp;
var n: Integer; b: Byte; w: Word; sm: SmallInt;
begin
  n := -1; b := 1; w := 1; sm := -1;
  writeln(n < b, '|', n < w, '|', sm < b, '|', n < 1, '|', b > n);
end.
```

| | output |
| --- | --- |
| FPC | `TRUE\|TRUE\|TRUE\|TRUE\|TRUE` |
| pxx x86-64 | `TRUE\|TRUE\|TRUE\|TRUE\|TRUE` |
| **pxx aarch64** | **`FALSE\|FALSE\|FALSE\|TRUE\|FALSE`** |

## Repro — C

```c
#include <stdio.h>
int main(void) {
  int neg = -1;
  unsigned char uc = 1; unsigned short us = 1;
  signed char sc = -1; char ch = 'a';
  printf("A %d %d\n", neg < uc, neg > uc);
  printf("B %d\n", neg < us);
  printf("C %d\n", sc < uc);
  printf("D %d %d\n", neg == -1, neg < 1);
  printf("E %d\n", uc > neg);
  printf("F %d\n", (int)uc + neg);
  printf("G %d\n", neg < ch);
  printf("H %d\n", neg <= uc);
  return 0;
}
```

```
gcc        : A 1 0  B 1  C 1  D 1 1  E 1  F 0  G 1  H 1
pxx x86-64 : A 1 0  B 1  C 1  D 1 1  E 1  F 0  G 1  H 1
pxx aarch64: A 0 1  B 0  C 0  D 1 1  E 0  F 0  G 0  H 0
```

**Only aarch64 is wrong.** i386, arm32 and riscv32 all print the gcc answer.
Independent of `-O0/1/2/3`.

## What is and is not affected

- Wrong: `<`, `>`, `<=`, `>=` where one side is a narrow **unsigned** type
  (`Byte`, `Word`, `unsigned char`, `unsigned short`, and plain `char` — which
  is unsigned on aarch64) and the other is a signed `Integer`/`int` holding a
  negative value. Reversing the operands (`uc > neg`) is wrong too.
- Correct: `neg == -1`, `neg < 1` (literal), `(int)uc + neg` — arithmetic is
  fine, and an explicit widening cast (`neg < (int)uc`) gives the right answer.
- **Both frontends.** This is not a C-typing bug; the Pascal repro above shows
  it with `Integer` vs `Byte`.

## Why it matters

C requires the narrow operand to be integer-**promoted to signed `int`**, so
the comparison is signed; Pascal likewise widens `Byte` into the signed
`Integer` domain. Producing the unsigned answer means a negative value reads as
~4 billion. `if (idx < buf[i])`, `while (n >= someByte)`, any bounds or
sentinel check mixing an int against a byte-sized quantity silently takes the
wrong branch on aarch64 and nowhere else. No crash, no diagnostic.

## Root cause (measured, FIXED)

The second of the two hypotheses this ticket was opened with. The aarch64
backend picked its condition codes with its own rule instead of the shared one
(`compiler/ir_codegen_aarch64.inc`, the `tkEq..tkGe` arm):

```pascal
EmitSetccA64Ex(op,
  TypeDivideUnsigned(IntToTypeKind(IRTk[left])) or
  TypeDivideUnsigned(IntToTypeKind(IRTk[right])));
```

`TypeDivideUnsigned` answers a *division* question — is this one operand an
unsigned dividend — and OR-ing it over both operands says "unsigned if either
side is unsigned". That is not the comparison rule. Integer promotion sends any
operand narrower than `int` to **signed** `int`, so a comparison against a
`Byte`/`unsigned char` is signed; `TypeCompareUnsigned` in `symtab.inc` already
encodes exactly this (including the csmith-hardened C sub-int and equal-rank
cases), and it is what x86-64 and the fused-jump path have always used. aarch64
was the only backend applying its own rule to comparisons — the other three use
`TypeDivideUnsigned` for division only, which is why they were all correct.

The fix is the one-line substitution. The case the old code was written for
(`bug-aarch64-unsigned-compare`, lua's `(size_t)x <= 0xFFFF...F`) still gets an
unsigned compare: `TypeCompareUnsigned` returns True for a genuinely wide
unsigned operand.

## Verification

Fixed compiler, self-host fixedpoint converged in one round.

- Pascal repro: `TRUE|TRUE|TRUE|TRUE|TRUE`, = FPC.
- C repro: `A 1 0 B 1 C 1 D 1 1 E 1 F 0 G 1 H 1`, = gcc.
- `tools/gcc_diff_probe.sh` against the fixed compiler: **0 new** on native,
  i386, arm32 and aarch64 (116 / 111 / 111 / 111 cases). The
  `integer-promotion-in-comparison` case is untagged again and must stay green
  on every target.
- `tools/gate.sh quick` GREEN (self-host fixedpoint + testmgr quick + the FPC
  seed canary, which ran because compiler/ was dirty).

## Coverage after the fix

`tools/gcc_diff_probe.sh --target aarch64` case
`integer-promotion-in-comparison` reports this today. Add the Pascal repro to
`tools/fpc_diff_probe.sh` — it has no cross mode, so a Pascal-side regression
here would otherwise only be caught through the C probe.

## Note on the sibling divergence in the same run

`shift-and-truncation-edges` also differs on arm32 **and** aarch64:
`(int)(char)0xFF` is `-1` under the x86-64 gcc oracle and `255` on both ARM
targets. That one is **correct** — plain `char` is unsigned in the ARM
procedure call standard — and needs a probe tag, not a fix. It is only
mentioned here so the two are not conflated.

## Gate

Track A: `make test` + self-host fixedpoint (byte-identical), plus the aarch64
cross run — `tools/gcc_diff_probe.sh --target aarch64` and
`tools/lib_cross_sweep.sh` (A/B its known reds; do not read them as new).

## Log
- 2026-08-05 — resolved, commit PENDING-COMMIT.

---
summary: "aarch64 only: comparing a signed Integer/int against a narrow UNSIGNED value (Byte/Word, unsigned char/short, and plain char) gives the wrong answer — `-1 < Byte(1)` is FALSE. Silent, both frontends, every -O level"
type: bug
track: A
prio: 85
---

# aarch64: `signed < unsigned-narrow` compares as unsigned

- **Type:** bug — Track A (aarch64 backend / comparison lowering)
- **Status:** urgent — **silent wrong value**, not a crash
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

## Hypothesis (NOT verified — do not record this as the cause)

Consistent with the data: the aarch64 backend compares in 64-bit registers and
the signed operand is not sign-extended to 64 bits when the other side is a
narrow unsigned load — `-1` sitting as `0x00000000FFFFFFFF` compares greater
than `1` under either signed or unsigned 64-bit comparison, which matches every
line above including `neg > uc` flipping to 1. The alternative — the compare
being emitted with unsigned condition codes because one operand's type is
unsigned — fits equally well. **Measure before writing a cause into this
ticket:** dump the emitted compare (`PXXDBG=a.ir:main`, or objdump the aarch64
binary) rather than reasoning about it, per `devdocs/dev/debugging-playbook.md`.

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

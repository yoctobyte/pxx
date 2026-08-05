---
summary: "i386/arm32: a C cast from a 64-bit integer to double/float TRUNCATES to the low 32 bits and sign-extends — (double)9007199254740991 is -1. Pascal is correct on the same targets, so it is the C cast lowering"
type: bug
track: C
prio: 80
---

# C: `(double)` of a 64-bit integer truncates to 32 bits on i386 and arm32

- **Type:** bug — Track C (C frontend, cast lowering). May hand off to A if the
  fix turns out to be in the shared conversion path.
- **Status:** done
- **Opened:** 2026-08-05
- **Found by:** Track B, cross-checking a new `strtod` hex-float path — a
  correct implementation produced `-1.9958403095347198e+292` for
  `0x1.fffffffffffffp+1023` on i386 and arm32 and the right answer everywhere
  else.

## Symptom

```c
unsigned long long m = 0x1FFFFFFFFFFFFFULL;   /* 2^53-1, exact in a double */
printf("%.17g\n", (double)m);
```

    x86-64 / aarch64 / riscv32 :  9007199254740991
    i386 / arm32               :  -1

## The rule, measured

The 64-bit value is **truncated to its low 32 bits and then converted as a
SIGNED 32-bit int**. Every case fits:

| value | low 32 bits | i386 result |
| --- | --- | --- |
| 2147483647 | 0x7FFFFFFF | 2147483647 (correct by luck) |
| 2147483648 | 0x80000000 | **-2147483648** |
| 4294967295 | 0xFFFFFFFF | **-1** |
| 4294967296 | 0x00000000 | **0** |
| 4886718345 | 0x23456789 | **591751049** |
| 9007199254740991 | 0xFFFFFFFF | **-1** |

Both signedness (`long long` and `unsigned long long`) and both float widths
(`double` and `float`) are affected; `(float)4294967296LL` gives 0. Anything
that fits in 31 bits is correct, which is why ordinary code does not notice.

## It is the C frontend, not the backend

The identical conversion in **Pascal is correct on the same targets**:

```pascal
var i: Int64; d: Double;
begin i := 9007199254740991; d := i; writeln(d:0:1); end.
```

gives `9007199254740991.0` on i386, arm32, riscv32, aarch64 and x86-64, matching
FPC. So the 32-bit backends have a working int64→double path and the C cast is
not using it.

Note **riscv32 is correct** as well — this is specific to i386 and arm32.

## Why urgent

Silent, and the wrong value is not a near miss: `-1` for nine quadrillion. Any C
code converting a file size, a timestamp, a byte count or a hash to floating
point is affected on two supported targets. It is invisible on x86-64, which is
where everything is tested.

## Repro

```
printf '#include <stdio.h>\nint main(void){ unsigned long long m = 0x1FFFFFFFFFFFFFULL;\n printf("%%.17g\\n", (double)m); return 0; }\n' > /tmp/u.c
./stable_linux_amd64/default/pinned --target=i386 /tmp/u.c /tmp/u_386 && qemu-i386 /tmp/u_386   # -1
./stable_linux_amd64/default/pinned /tmp/u.c /tmp/u_64 && /tmp/u_64                             # 9007199254740991
```

## Separate, do not conflate

`strtod("0x1p-1074")` (the smallest subnormal) returns 0 on **riscv32** only.
That is soft-float flush-to-zero in the subnormal range, a different question
from this one, and not chased — the user has asked that float
rounding/representation work not absorb time. Recorded here so the next reader
knows the two divergences in that test row are unrelated.

## Log
- 2026-08-05 — resolved, commit 9f42ddc67.

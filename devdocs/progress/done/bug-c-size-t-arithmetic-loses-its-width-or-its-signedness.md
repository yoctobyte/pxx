---
track: C
prio: 50
type: bug
status: done
found: 2026-09-27
found-by: frankD
owner:
summary: "`sizeof` is typed as the native unsigned kind, not as size_t: on ILP32 (i386, arm32, riscv32) `-1 < sizeof(int)` answers 1 and `i / sizeof(int)` divides signed; on LP64 (x86-64, aarch64) `sizeof a - sizeof b` wraps at 2^32 (4294967292, gcc 2^64-4). SILENT, and the same on v445 (caf21ac399f1)."
---

# size_t arithmetic loses its width or its signedness

```c
int a; double b; int i = -8;
-1 < sizeof(int)        /* i386/arm32/riscv32: pxx 1, gcc 0 */
i / sizeof(int)         /* ILP32: pxx -2, gcc 1073741822 */
sizeof a - sizeof b     /* x86-64/aarch64: pxx 4294967292, gcc 18446744073709551612 */
```

Found by the cross-target differential over test/c*.c (pxx --target=T under
qemu against gcc -m32 for ILP32 and gcc for LP64), 2026-09-27.

## Resolution (2026-09-28)

The sizeof result kind is size_t's for the target: tyUInt32 when
TARGET_PTR_SIZE is 4, tyUInt64 otherwise (compiler/cparser.inc, the sizeof
node). Fixture `test/c_size_t_arithmetic_keeps_width_and_sign.c` (16 rows,
C truths in SIZE_MAX, one .expected for all five targets): v445 answers 4 to 6
rows wrong on each target, this build none.

---
track: A
prio: 55
type: bug
blocked-by: []
summary: "`wait4()` does not write its `rusage` out-parameter on riscv32, and does on every other cross target. MEASURED 2026-09-12 on borg, full native tier, job `test-core#2020` (`test/c_crtl_wait.c`): `expect_same MISMATCH [riscv32/c_wait26]`, `- wait4-rusage rusage=written` / `+ wait4-rusage rusage=UNTOUCHED`. i386, arm32 and aarch64 all OK on the same row, so it is the riscv32 syscall path and not the C test or the crtl shim. NOT environmental — found alongside a multilib fix on that box and explicitly separated from it: the other two rows in that tier went green when multilib landed, this one did not move. One-target width/ABI shape, which is the class x86-64-only development is structurally blind to. No skip was added and nothing was deleted."
---

# wait4 leaves rusage untouched on riscv32

Reported by the Track T seat on borg, 2026-09-12, from a full native tier at
`051b229aa`. Flagged rather than chased, because it was not what that seat was
sent after.

## The measurement

```
test-core#2020  test/c_crtl_wait.c
  expect_same MISMATCH [riscv32/c_wait26]
  -  wait4-rusage     rusage=written
  +  wait4-rusage     rusage=UNTOUCHED
```

i386, arm32 and aarch64 pass the same row. **One target, same source, same
harness** — so the discriminator is the riscv32 syscall path.

## Why it is worth more than its prio suggests

This is the shape CLAUDE.md names as structurally invisible: the dev loop,
`gate.sh quick` and the pin all run on x86-64, so a defect that only appears on
one 32-bit cross target has no instrument pointed at it except the native tier
that found this. It was caught by breadth, which is what breadth is for.

`rusage=UNTOUCHED` is also the **default-collision** shape: an out-parameter that
was never written reads as a zeroed struct, which for most fields is a plausible
value. The test is right to assert *written* rather than a field's contents —
anything asserting the numbers would have to pick values, and a zero would pass.

## Where to start

`wait4` on riscv32: whether the syscall is issued with the rusage pointer at all,
and whether the argument register for the 4th parameter matches the kernel's
expectation on that ABI. Check the sibling `wait3`/`getrusage` paths in the same
file — **if one arm of a double case is fixed, grep for the sibling before
closing.** Compare against the arm32 path, which is the nearest working 32-bit
one.

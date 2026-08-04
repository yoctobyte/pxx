---
summary: "PAL_OPEN_DIRECTORY used the x86 value on every target, so the entire directory-listing surface was dead on arm32 and aarch64 — and opening a regular FILE with the flag wrongly SUCCEEDED there"
type: bug
track: B
prio: 70
---

# `O_DIRECTORY` had the x86 value on ARM — directory listing was dead on arm32/aarch64

- **Type:** bug — Track B (library / PAL)
- **Status:** done
- **Resolved:** 2026-08-04 in `0f84feea3` (verified on origin/master after the rebase)
- **Opened:** 2026-08-04
- **Found by:** `tools/lib_cross_sweep.sh` — `lib_directory` differed from its
  x86-64 output on both arm32 and aarch64.

## Symptom

    PalOpen('/tmp', PAL_OPEN_READ or PAL_OPEN_DIRECTORY, 0)

    x86-64 / i386 / riscv32 :  fd 3
    arm32 / aarch64         :  -22  (EINVAL)

`ListDirectory` opens with that flag and returns `False` the moment the open
fails, so **every directory listing on arm32 and aarch64 returned nothing**, with
no error visible to the caller beyond a `False`.

## Root cause

`O_DIRECTORY` is one of the few `open()` flags Linux does **not** define
uniformly across architectures. `lib/rtl/platform.pas` had a single constant:

```pascal
PAL_OPEN_DIRECTORY = $10000;      { x86-64 / i386 / riscv32 }
```

but arm and aarch64 use **`$4000`** (they swap the bit with `O_DIRECT`).

## Wrong in BOTH directions, which is why it hid

Measured per target, with the negative control included:

| target | dir + `$10000` | dir + `$4000` | **file** + `$10000` | **file** + `$4000` |
| --- | --- | --- | --- | --- |
| x86-64 | fd 3 | EINVAL | ENOTDIR | **fd 3** |
| i386 | fd 3 | EINVAL | ENOTDIR | **fd 3** |
| riscv32 | fd 3 | EINVAL | ENOTDIR | **fd 3** |
| arm32 | EINVAL | fd 3 | **fd 3** | ENOTDIR |
| aarch64 | EINVAL | fd 3 | **fd 3** | ENOTDIR |

So on ARM the wrong value did not merely fail to open directories — it also made
opening a **regular file** succeed where the flag exists precisely to reject
that. A caller using `O_DIRECTORY` as a type check got the opposite answer.

## Fix

`lib/rtl/platform.pas` — the constant is now
`{$if defined(CPU_ARM32) or defined(CPU_AARCH64)}` `$4000` `{$else}` `$10000`.
Read off each target by measurement rather than from a header, including the
negative control. The other flags defined there (CREATE / EXCL / TRUNC /
APPEND) are uniform on every Linux target we build for, and were checked rather
than assumed. The ESP backend keeps its own value (newlib, not Linux syscalls).

## Test

`test/lib_directory.pas` gains two rows, and the way they are written is the
point:

    odir-dir=1              opening a DIRECTORY with the flag must succeed
    odir-file-rejected=1    opening a FILE with the flag must FAIL

They assert **behaviour, not the constant**, so they are valid on any target and
a wrong value breaks one or the other wherever the test runs. That matters
because `lib-test` only ever runs x86-64: a test that merely listed a directory
would have stayed green through this bug indefinitely. Both rows fail on arm32
and aarch64 without the fix; all three cross targets match x86-64 with it.

## Coverage note

Found only because `tools/lib_cross_sweep.sh` now exists. Nothing else in the
tree runs `lib/rtl` on a non-x86-64 target — `lib-test` is native-only and Track
T's cross matrix does not include the lib tests.

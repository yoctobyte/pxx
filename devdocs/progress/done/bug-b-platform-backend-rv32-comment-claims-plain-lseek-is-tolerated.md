---
slug: bug-b-platform-backend-rv32-comment-claims-plain-lseek-is-tolerated
track: B
prio: 30
type: bug
found: 2026-08-30
found-by: frankS
owner: frankB
status: done
---

# platform_backend's rv32 block says qemu tolerates plain lseek; strace says no

`lib/rtl/platform/posix/platform_backend.pas`, the `CPU_RISCV32` constant block:

> *"lseek is llseek(62) with a split 64-bit offset — PalSeek below only passes
> small offsets, and **qemu-user tolerates the plain form for them**"*

Measured under `qemu-riscv32 -strace` on 2026-08-30, calling the 3-arg form:

```
openat(AT_FDCWD,"test/hello.pas",O_RDONLY) = 3
llseek(3,0,2,NULL,UNKNOWN)                 = -1 errno=22 (Invalid argument)
read(3,0x2b2ad050,-22)                     = -1 errno=14 (Bad address)
```

It is not tolerated. `_llseek` is `(fd, off_hi, off_lo, loff_t *result, whence)`
— the 3-arg form leaves the result pointer NULL, the kernel returns EINVAL, and
the -1 flows onward as a size.

## The comment is stale, not wrong-headed — and the code below it already knows

`PalBackendSeek` in the *same file* has carried the correct split for some time:

```pascal
{$ifdef CPU_RISCV32}
  { rv32 syscall 62 is _llseek(fd, off_hi, off_lo, loff_t *result, whence), NOT
    plain lseek — the 3-arg form left the result pointer NULL and the kernel
    faulted (EFAULT). }
  res := 0;
  r := __pxxrawsyscall(SYS_lseek, handle, (offset shr 32) and $FFFFFFFF,
                       offset and $FFFFFFFF, Int64(@res), whence);
```

So the *implementation* was fixed and the *constant block's comment* was not.
Two statements in one file that contradict each other, and the wrong one is the
one a reader meets first — it sits beside the `SYS_lseek = 62` definition, which
is exactly where someone goes to write a new caller.

## Why it is filed rather than shrugged at

It cost a debugging cycle today. `PXXSysLseek` in `compiler/builtin/builtinheap.pas`
was given a riscv32 arm using the plain 3-arg form **on the strength of this
comment**, and produced a `LoadFile` that returned an empty string with no error
anywhere — the "plausible wrong value far from the cause" shape. The strace above
is what settled it. The arm now mirrors `PalBackendSeek`.

A comment that asserts a runtime behaviour is a claim, and this one is testable
in one command. `devdocs/dev/debugging-playbook.md`'s rule applies to prose too:
the comment was reasoning, the strace was measurement.

## Fix

Correct the sentence in the `CPU_RISCV32` block to say 62 is `_llseek` and that
callers must pass the split offset and a result pointer, pointing at
`PalBackendSeek` as the reference. Grep for any other 3-arg `SYS_lseek` caller
on rv32 while there — `PalSeek`'s own path is the one the comment was excusing,
and whether IT is correct today was not checked as part of this finding.

Trivial change; filed because the file is Track B's and the finding came out of
a Track A/S grant.

## Resolved 2026-08-30 (frankB)

Comment corrected in the `CPU_RISCV32` block of
`lib/rtl/platform/posix/platform_backend.pas`. It now states that 62 is
`_llseek(fd, off_hi, off_lo, loff_t *result, whence)` and that rv32 has no plain
lseek at all, says what a 3-arg call actually does (NULL result pointer →
EINVAL → -1 flowing onward as a size), points at both correct implementations —
`PalBackendSeek` below it and `PXXSysLseek` in
`compiler/builtin/builtinheap.pas` — and carries the qemu-strace that settles
it, dated. The old sentence asserted a runtime behaviour with nothing that
re-checked it; the replacement carries its own evidence, which is the only form
that does not rot silently.

### The grep the ticket asked for: clean

Every `SYS_lseek` **call site** in the repo, both of them:

```
lib/rtl/platform/posix/platform_backend.pas:417   split 5-arg form, rv32 arm
lib/rtl/platform/posix/platform_backend.pas:421   plain 3-arg form, {$else} arm
```

plus `PXXSysLseek` in `compiler/builtin/builtinheap.pas`, which already carries
the identical rv32 split (it was fixed by the Track A/S session that filed this).
No third caller exists, and no 3-arg rv32 path survives anywhere.

### `PalSeek`'s own path — the question this ticket left open — is CORRECT

The filing noted that `PalSeek` was what the stale comment was excusing and that
nobody had checked whether it is right today. It is, and this is measured rather
than reasoned. `PalSeek` → `PalBackendSeek`, which takes the rv32 split arm.
Cross-built `test/lib_platform.pas` for riscv32 and ran it under qemu:

```
llseek(3,0,0,0x2b2aabb8,SEEK_CUR) = 0
llseek(3,0,0,0x2b2aabd8,SEEK_END) = 0
llseek(3,0,0,0x2b2aabd8,SEEK_SET) = 0
```

Five arguments, a **real result pointer** rather than NULL, all three returning
0 — and the program's own output agrees end to end (`tell=2`, `file=io:2:2`,
exit 0). Compare the failing form in the filing: `llseek(3,0,2,NULL,UNKNOWN) =
-1 errno=22`.

### Verification

- host build of `test/lib_platform.pas` against `$(PXX_STABLE)`: **OK**
  (does not enter the edited arm);
- **riscv32 cross build: OK**, 425928 bytes — this is the one that matters, since
  the comment lives inside a `const` block only that target compiles;
- run under `qemu-riscv32`: **exit 0**, output as above.

No compiler was rebuilt; everything was built with `$(PXX_STABLE)`.

### One line this creates for Track A

`PXXSysLseek`'s comment in `compiler/builtin/builtinheap.pas` ends with *"NOTE
the sibling comment in that same file's rv32 block still says the plain form is
tolerated by qemu-user"*. That clause is now false — it was true when written
this morning and this ticket is what falsified it. `compiler/builtin/**` is Track
A's ground so it is not touched here; filed as
[[chore-a-trim-the-stale-cross-reference-in-pxxsyslseek-s-rv32-comment]]. It is a
three-line deletion, and it is filed rather than shrugged at for precisely the
reason this ticket exists.

## Log
- 2026-08-30 — resolved, commit 06b9617d9.

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

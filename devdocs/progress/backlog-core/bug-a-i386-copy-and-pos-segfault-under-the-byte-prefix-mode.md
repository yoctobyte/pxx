---
type: bug
track: A
prio: 80
status: open
summary: Under -dPXX_SHORTSTRING on i386, Copy()/Pos() on a string[N] segfault;
  correct in the default mode and on all four other targets in both modes.
---

# i386: Copy and Pos segfault under the byte-prefix mode

**Blocks the phase-4 flip on i386.**

```pascal
var s: string[10];
begin s := 'abcdef'; WriteLn('[', Copy(s,2,3), '] ', Pos('cd', s)); end.
```

| target | default | `-dPXX_SHORTSTRING` |
| --- | --- | --- |
| **i386** | `[bcd] 3` | **SIGSEGV** |
| x86-64 / arm32 / aarch64 / riscv32 | `[bcd] 3` | `[bcd] 3` |

Distinct from
`bug-a-string-concat-segfaults-on-x86-64-under-the-byte-prefix-mode`, which is
x86-64 ONLY and leaves `Copy`/`Pos` working there. **The two crashes are on
disjoint targets**, so they are unlikely to be one cause and each needs its own
repro.

Found by a 20-probe both-modes suite across five targets. **x86-64 shows this
row clean** — the native-only blind spot again.

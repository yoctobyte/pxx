---
track: N
prio: 30
type: bug
blocked-by: []
summary: "`os.getpid()` answers `undefined variable (os)` — the member is absent, not the module, exactly like `os.rmdir` was before it was fixed on 2026-09-12. Split out of bug-n-os-has-no-rmdir as its RESIDUAL rather than fixed alongside it, because the two are not the same size: rmdir reuses an existing syscall number (NR_UNLINKAT with AT_REMOVEDIR, since Linux has no at-family rmdir) and cost nothing cross-target, while getpid has no NR_ constant at all and needs a number added to all SIX per-target tables in compiler/builtin/pypal.pas (x86-64/i386/aarch64/arm32/wasm32-as-unsupported/riscv). Low prio because no program in any umbrella calls it — it surfaced in a probe written to characterise the rmdir diagnostic, not in the lekkerzeilen closure."
---

# os has no getpid

```python
import os
print(os.getpid())   # error: undefined variable (os)
```

The diagnostic is the same misleading one [[bug-n-os-has-no-rmdir]] documents:
an absent MEMBER of a module that resolves fine is reported as the module
being an undefined variable, so the reader looks at the import.

## Why this is not a five-line fix

`compiler/builtin/pypal.pas` holds six `NR_*` blocks, one per target
(`grep -c 'NR_' ` answers 153 constants across them). `rmdir` needed none of
them — `PyPalRmdir` reuses `NR_UNLINKAT` with `PYPAL_AT_REMOVEDIR = 512`, and
the comment beside that constant says so in its own words: *"this reuses
NR_UNLINKAT rather than adding a syscall number to all six tables."*

`getpid` has no such shortcut. It needs six correct numbers (x86-64 39,
i386 20, aarch64 172, arm32 20, riscv 172, wasm32 `-1`/unsupported — **those
are from memory and must be re-derived from the kernel headers, not copied
from this ticket**, per the rule that an assertion written from a report pins
the report).

## Cross-target hazard worth knowing before starting

Six hand-written numbers is exactly the shape where x86-64 is right and a
32-bit target is silently wrong, and the dev loop only runs x86-64 — so assert
a RELATION, not a constant, or add a row per target. `PyPalSupported` already
gives the wasm32 arm somewhere honest to land.

## Residual this ticket does NOT cover

`shutil.rmtree` is still absent (`no member rmtree came of the qualifier
shutil`), and `tempfile.TemporaryDirectory` cannot be written without it.
That belongs to track B / lib/rtl, not here.

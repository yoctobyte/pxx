---
track: A
prio: 35
type: bug
status: open
found: 2026-08-30
found-by: claude-A
---

# The "no FPU" diagnostic tells you to `uses softfloat`, and doing so changes nothing

On a bare ESP target the compiler refuses a float operation with:

```
this target has no FPU and the soft-float kernel __pxx_d2i_rne is not linked;
add `uses softfloat` to the program
```

**Following that advice does not work.** Measured on both bare ESP targets:

| program | bare xtensa | bare riscv32 |
| --- | --- | --- |
| `uses builtin;` | fails (two undefined names) | same, line for line |
| `uses softfloat, builtin;` | **same kernel error, same line** | same |

`softfloat` is **found** — no unit-not-found diagnostic appears — and the check
still refuses.

## Why this is worth a ticket rather than a shrug

A diagnostic that names a remedy is stronger than silence, and a *wrong* remedy
is weaker than silence: it costs the reader a real attempt and then leaves them
unsure whether they did it wrong. Two sessions have now hit this line while
chasing something else.

## The two candidate causes, deliberately not guessed between

1. The kernel-presence check does not see `softfloat`'s kernels (wrong predicate,
   wrong point in the pipeline, or the unit's symbols are not registered under
   the names the check looks for).
2. The advice is stale — `softfloat` no longer provides these kernels, or never
   provided them for the bare ESP profile — and the message should say something
   else, or nothing.

These have opposite fixes. Whoever takes it should determine which **before**
editing the string, since fixing the message when the check is broken would hide
a real defect behind a more honest-sounding sentence.

## Provenance

Found while working
[[bug-a-builtin-pas-calls-a-declaration-that-esp-compiles-out]]; the kernel
errors are the queue that appears once that unit's guards are made to work. Not
chased there because it is a separate defect with a separate cause.

---
track: A
prio: 20
type: bug
blocked-by: []
summary: "`FindTypeAlias failed to find puint8! AliasCount=36` is printed to stderr during a compile that then SUCCEEDS. Either the lookup failure is real and something silently fell back to a wrong type, or the message is a stale debug print that should not be in a release build. Both readings are defects; which one it is has not been established."
---

# `FindTypeAlias failed to find puint8!` on stderr, compile continues

- **Type:** bug (compiler core) — **Track A**. `FindTypeAlias` and the alias
  table are shared ground, not frontend ground; a core internal printing to
  stderr during a normal successful compile is A's to answer.
- **Filed:** 2026-08-20 by frank3, observed while driving the rtl-generics
  corpus stage for [[feature-pascal-corpus-generics]] (generics.defaults).
- **Possible loose end, not a new defect:** `PUInt8` was cleared as an earlier
  wall of the same corpus climb. Check that fix first — this may be its
  remainder rather than anything new.

## What was seen

The line appears on stderr, once, during a compile that exits 0 and produces a
working binary. `AliasCount=36` suggests the table is populated and `puint8`
specifically is not in it.

## The fork, which is why this is filed rather than fixed

Two readings, and they want opposite fixes:

1. **The lookup failure is real.** Something asked for `puint8`, did not get
   it, and carried on with whatever the failure path leaves behind. Then this
   is a silent wrong type with a warning attached, and the priority above is
   too low.
2. **It is a leftover debug print.** The caller handles a miss correctly and
   the message is noise that should never have shipped — a compiler that
   prints internal diagnostics on a successful build trains everyone to ignore
   its stderr, which is how the *next* real message gets missed.

Establish which before fixing: find the `FindTypeAlias` call site that misses,
and read what it does with the failure. Do not infer it from the wording.

## Repro

Not yet reduced — seen only in the full rtl-generics drive. Reducing it is the
first task; `grep -rn "failed to find" compiler/` locates the print.

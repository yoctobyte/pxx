---
summary: "optdiff finds -O3 changing observable behaviour in two C tests — cmath_sign_bits returns rc 42 against the baseline's rc 1, and cmath_no_pascal_hijack's output differs at equal rc"
type: bug
track: O
prio: 65
status: done
owner: claude-ACPN
---

# `-O3` diverges from the baseline on two cmath tests

- **Type:** bug (Track O — optimization; file-owned by Track A per CLAUDE.md)
- **Found:** 2026-08-09 by the Track T watcher on plexus, opt tier, sha
  `dcfe7a6f8f0f`. Filed by Track T per "T owns the tool, never the bug".

## What optdiff reports

```
OPT DIFF -O3: test/cmath_no_pascal_hijack.c (rc 0 vs 0)
OPT DIFF -O3: test/cmath_sign_bits.c        (rc 42 vs 1)
optdiff shard 1/12: pass=102 skip=16 diff=2
```

A real run: wall 563.6s, `compiler_sha256 9d511d465b6f`, 102 passing beside
the two diffs.

**`cmath_sign_bits` is the sharp one.** Same program, same source, different
**exit code** — 42 optimized against 1 unoptimized. An `-O3` pass is changing
observable behaviour, not just code shape. `cmath_no_pascal_hijack` differs in
OUTPUT at equal rc, which is the same class one step quieter.

Sign-bit handling is exactly where this hurts: a wrong `-0.0`, a comparison
folded on the assumption that `x == -x` implies zero, or a `copysign`
strength-reduced past its sign semantics all produce a plausible wrong value
rather than a crash — the failure mode `devdocs/dev/debugging-playbook.md`
calls the expensive one.

## Repro

```
tools/testmgr.py --tier opt --job 'optdiff#shard1/12'
```

or directly, which is what optdiff does per program: build at the baseline
level and at `-O3`, run both, compare rc and stdout.

## Why this sat unticketed

Track T's own fault, now fixed. The stub-filing dedupe (`81cc6cadb`) keyed on
test SOURCE, and every optdiff shard carries `tools/optdiff.sh` as its src —
the driver, not the program — so one already-ticketed shard silenced the rest.
Fixed in `5b7b3691d`: dedupe now requires the targets to differ. A second flaw
found alongside it — the dedupe was matching a ticket in `done/` — is fixed
too. Neither changes anything about the findings below; they are real.

## Note on scope

Two diffs in one shard, both cmath, both sign/format adjacent — likely ONE
cause rather than two. Worth diffing the emitted code for `cmath_sign_bits`
between `-O2` and `-O3` first and identifying which pass is responsible, before
treating them separately.

## Gate

`tools/testmgr.py --tier opt` with `optdiff#shard1/12` clean, and no new diffs
in the other eleven shards.

## Log
- 2026-08-10 — resolved, commit PENDING-COMMIT.

## Resolution (2026-08-10) — already fixed at HEAD by intervening crtl work

**Not an `-O3` pass.** Both diffs are gone, and the fix was in `lib/crtl`, not
in the optimizer.

### Verified at HEAD

- `tools/optdiff.sh --shard 1/12` — the shard that reported it —
  **`pass=104 skip=16 diff=0`**. The two diffs did not move or become skips;
  they became passes (102 → 104).
- Both programs hand-run at `-O0 / -O1 / -O2 / -O3`: identical stdout and exit
  code at every level, and both match the **gcc oracle**
  (`cmath_sign_bits` 42, `cmath_no_pascal_hijack` 0).
- The ticket's hunch that two diffs meant ONE cause looks right.

### What fixed it

`bab16e1b3` *"fix(crtl,C): C owns its math — and the real reason it could not"*
(2026-08-10), which lands between the reported sha `dcfe7a6f8f0f` and HEAD and
resolves `...-pascal-math-names-hijack-libc-through-pxxcio` — the ticket
`cmath_no_pascal_hijack.c` exists to pin. Its core finding: `<inttypes.h>`'s
declarations had no sibling `.c`, so those symbols **silently resolved against
glibc**, and `math.c`'s `nan()` compiled only by riding an accidental
program-wide `<stdlib.h>` from `pxxcio`'s `uses math`.

`cmath_sign_bits` calls `nan("")` three times, and its first NaN assertion
(`signbit(copysign(nan(""), -1.0))`) is exactly the shape that fails when
`nan()` is bound to a foreign implementation. `9f941deb1` (crtl's integral-part
family losing `-0.0`) is adjacent and may have contributed.

**Stated as the limit of the evidence:** the *level-sensitivity* — why the
glibc binding produced rc 1 at the baseline and rc 42 at `-O3` — was **not
independently reproduced**, because that would require rebuilding the compiler
at `dcfe7a6f8f0f`. A binding that depends on which externals survive inlining
is a plausible mechanism, not a measured one. It is recorded as a hypothesis,
not a conclusion — the diff itself is confirmed gone by the shard.

### Found while verifying — filed, not fixed here

`tools/optdiff.sh` compiles with a bare `$(CC) -O<n> file`, so the **9 of 18
`test/cmath*.c` that need `-Ilib/crtl/include -Ilib/crtl/src`** (flags the
Makefile does pass) fail to compile and land in the `skip=16` bucket. Half the
cmath family — including every correctly-rounded libm test, which is exactly
where an `-O3` float pass would surface — is invisible to the O-level sweep.
Run by hand with the right flags, **all 18 are identical across -O0/-O2/-O3**.
Filed as [[bug-t-optdiff-skips-tests-that-need-compile-flags-the-makefile-passes]]
(Track T owns the tool).

**No code change in this lane**; nothing to gate.

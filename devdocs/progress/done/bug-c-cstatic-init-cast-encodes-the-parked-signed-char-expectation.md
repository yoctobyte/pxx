---
summary: "cstatic_init_cast.c was written during the 2-hour window when plain char was signed, so its c3 check expects -1. The remap was reverted at 17:00 and the test was stranded — the compiler is behaving as ticketed, the expectation is not"
type: regression
track: C
prio: 60
status: done
---

# `cstatic_init_cast.c` encodes an expectation that was reverted an hour later

- **Type:** regression (test expectation, NOT a codegen bug) — **Track C**
- **Filed:** 2026-08-03 by `claude@xeon` (Track T) from `test-core`.
  Reproduces at HEAD with a compiler rebuilt at `917224abd`.

## Not a compiler bug — read this first

The compiler is doing what the board says it does. `test/cstatic_init_cast.c`
compiles clean and exits **5**, which is:

```c
if (c3[0] != CH_FF) return 5;      /* CH_FF is -1 on x86-64/i386 */
char c3[2] = { (unsigned char)0xFF, 0 };
```

`c3` is a plain `char`. The check only passes while plain `char` is SIGNED —
and it is not, by deliberate decision:

```
# PARKED, not deleted: cchar_plain_signedness.c states gcc's answer and is
# correct C — plain `char` is signed on x86-64/i386. pxx still zero-extends it
# at runtime ...
# blocked-by: bug-cfront-plain-char-is-unsigned-and-folds-inconsistently
```

Measured at HEAD: `(char)-1 < 0` is false, and `c3[0]` reads back as 255. Both
are the documented current behaviour.

## How it got stranded — a two-hour window

| time | commit | effect |
|---|---|---|
| 12:52 | `07414aa89` | plain `char` → `tyInt8`: signed. Red'd five jobs ([[bug-c-plain-char-lost-its-type-identity-not-just-its-signedness]]) |
| **14:04** | `eee8c4998` | **this test written**, with `CH_FF = -1` guarded on `__x86_64__` — green at that moment |
| 17:00 | `917224abd` | remap reverted, identity restored, signedness back to unsigned |

The test's own header says it knew: *"Note c3/u2: the array element is a plain
`char`, which is SIGNED on x86-64/i386, so 0xFF reads back as -1 there — the two
rules interact, hence the guard."* That was true for two hours.

`cchar_plain_signedness.c` — the test whose whole subject is signedness — was
parked in the same commit that reverted the remap, correctly and with a note.
This one was missed because its dependence on signedness is **one line inside a
test about something else** (casts in static aggregate initializers). That is
the general hazard worth noting: a test acquires a dependency on a behaviour it
is not about, and a later revert of that behaviour strands it.

## Fix — same treatment as the sibling, one line

Guard or park the `c3` expectation only, mirroring `cchar_plain_signedness.c`:
`blocked-by: bug-cfront-plain-char-is-unsigned-and-folds-inconsistently`, and
**do not weaken it** — `-1` is gcc's answer and stays the target. The other 19
checks in the file are about static-init cast folding, are unaffected, and
should keep running; only c3 depends on signedness.

## Gate

`test/cstatic_init_cast.c` exits 42 at HEAD, and when the signedness fix lands
the c3 expectation is restored to `-1` on x86-64/i386 rather than rewritten.

## Resolved 2026-08-03 (claude-AC@opus5) — by the real signedness fix, not by touching the test

Correct diagnosis, and it stopped being true an hour later. The analysis was
made against the revert-only tree, where plain `char` was unsigned again and the
expectation was genuinely stranded. Commit `5b78c4e4d` then landed the actual
fix: plain `char` is signed on x86-64/i386 once more — but as a PROPERTY applied
at the C integer-promotion sites (`CPromoteChar`), not by remapping the type onto
`tyInt8`, so character identity survives this time.

So `CH_FF` is `-1` again and `cstatic_init_cast.c` passes on its own terms. The
expectation was right all along; the compiler caught up to it.

Verified at `d3afe9dae` with a compiler rebuilt to a self-host fixedpoint (not
the binary left on disk): `test/cstatic_init_cast.c` exits **42**, and gcc exits
42 on the same source.

`test/cchar_plain_signedness.c` is un-parked and gated again, expectations
untouched. Nothing in either test was weakened to close this.

See [[bug-cfront-plain-char-is-unsigned-and-folds-inconsistently]] for the fix
and its gcc oracle sweep.

## Log
- 2026-08-03 — resolved, commit 5b78c4e4d.

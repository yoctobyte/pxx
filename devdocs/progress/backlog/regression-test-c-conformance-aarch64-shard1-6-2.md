---
prio: 70
track: A
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-c-conformance-aarch64#shard1/6 red at b695bcb4b192 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T14:03:47Z
- **Test source:** compiler/.pascal26.fixedpoint tools/run_c_conformance.sh

## Repro
`tools/testmgr.py --tier full --job 'test-c-conformance-aarch64#shard1/6'` at b695bcb4b19264847cedc6c01678d4e298d14cfb

## Range
> **The named sha `b695bcb4b192` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `b695bcb4b192`, last good `4d3f8a4eac00`, 7 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
FAIL 00170.c — compile error:
pascal26:73: error: target aarch64: variadic external call with more than 8 arguments not supported
(tail)
self-host fixedpoint: verified — 1 round(s), 82583d52f672 --shard 1/6
FAIL 00170.c — compile error:
    pascal26:73: error: target aarch64: variadic external call with more than 8 arguments not supported
      near:       >>>  unit builtinheap 
test-c-conformance-aarch64: 36 pass, 1 fail, 0 skip (of 37)
test-c-conformance-aarch64: FAILURES: 00170.c(compile)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## CAUSE IDENTIFIED AND FIXED — but DO NOT CLOSE on that alone

**The cause is fixed; this job is not yet observed green.** Those are different claims and the
distinction is the ticket's, not a formality.

frankA found one expression behind **both** symptoms — the >8-param refusal and the
conformance output mismatch:

```pascal
if ProcExternal[procIdx] or ProcCdecl[procIdx] then        { the bug }
if ProcExternal[procIdx] or (ProcCdecl[procIdx] and (not CProgramMode)) then   { the fix }
```

The C frontend marks **every** C function `ProcCdecl`, and a C-defined function is not
`ProcExternal` — so the aarch64/arm32 direct-call sites dragged every function of every C
program onto the C-ABI marshalling path, where `cparser.inc`'s own prologue spill is
**positional** on exactly those two targets. A 9-param C function hits the C-ABI path's arg
limit (the refusal); `mix(int,double,int,double)` makes an AAPCS call into a positional
prologue and prints garbage (the mismatch). x86-64 was never affected because cparser's
x86-64 spill really is SysV — **the two targets whose halves disagree are exactly the two
that broke.**

Fixed forward, not reverted: the prologue arms are correct and tested, only the call-site
predicate was wrong.

### Why this ticket stays open

**The lua tree and the c-testsuite corpus are both ABSENT from this checkout.** frankA
reproduced the *mechanism* from synthetic C — a new `ccross_cdecl_cmode.c` that fails to
build at `83a767151ffa` with both reported error messages verbatim, verified by stashing the
fix and rebuilding at that sha rather than by reasoning — and says so itself:

> My evidence is that the cause is fixed — **not that those five jobs are green.**

So: **Track T re-runs these jobs against current HEAD and that verdict closes them.** A fixed
cause plus an unrun job is exactly the shape that produced today's other findings; do not
substitute one for the other.

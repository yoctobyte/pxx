---
slug: chore-t-lint-fall-open-target-chains-without-the-false-positives
title: "Lint per-target dispatch chains that fall open — and the naive version of this check is 5-for-5 wrong, so the value is entirely in the three distinctions it must make"
track: T
prio: 30
type: chore
blocked-by: []
status: new
owner: ""
found: 2026-08-29
found-by: pxx-a5
summary: "A per-target {$ifdef CPU_x} run with no terminal arm is the shape behind bug-a-per-cpu-ifdef-chains-in-builtinheap-fail-open (5 instances, fixed). Sweeping the tree finds 21 more such runs — and 5 of 5 inspected are NOT defects: they are const tables (an armless target gets an undefined-identifier COMPILE ERROR, i.e. fail-closed) or function bodies with a pre-chain initialiser that is deliberate and documented. A naive lint would have filed 21 phantom tickets, two of them into Track A. The ticket is the three distinctions, not the grep."
---

# Lint fall-open target chains — the grep is the easy 10%

## Where this came from

`bug-a-per-cpu-ifdef-chains-in-builtinheap-fail-open` fixed five real instances
in `compiler/builtin/builtinheap.pas`, where a run of `{$ifdef CPU_x}` blocks
with no terminal arm left `Result` **never assigned** on riscv32, wasm32 and
xtensa/IDF. The general rule it yielded is worth linting:

> A dispatch chain whose last arm is a REAL TARGET rather than an error is a
> fall-open chain wearing the shape of an exhaustive one.

## The sweep, and why its output is not a defect list

A mechanical scan for per-CPU `{$ifdef}` runs with >=3 arms and no terminal
`{$else}` returns **21 sites** beyond the ones fixed:

```
compiler/builtin/builtin.pas:423        lib/rtl/pxxcio.pas:299,311,403
compiler/builtin/pypal.pas:88           lib/rtl/random.pas:272
lib/rtl/ansiterm.pas:108,125,142,159    lib/rtl/scheduler.pas:79,99,149,471
lib/rtl/baseunix.pas:103                lib/rtl/sockets.pas:222
lib/rtl/palparallel.pas:143,163         lib/rtl/sysutils.pas:1562
lib/rtl/palpthread.pas:134              lib/rtl/platform/posix/platform_backend.pas:120
```

A second heuristic — back-scan for a pre-chain `Result :=` — classified six of
them as "NO DEFAULT, Result never assigned". **Five were inspected by hand.
All five were wrong**, in three distinct ways:

| site | heuristic said | actually |
| --- | --- | --- |
| `builtin.pas:423` `Randomize` | Result never assigned | a **procedure**; `r := 0` before the chain, and a comment documents the armless case as deliberate weak entropy |
| `pypal.pas:88` | Result never assigned | not a routine — a per-arch **const table**, with `PYPAL_HAVE` as its own exhaustiveness marker |
| `scheduler.pas:79` | Result never assigned | a `const SYS_gettid = ...` chain; an armless target gets an **undefined identifier compile error** — fail-CLOSED |
| `palpthread.pas:134` | Result never assigned | `__pxx_pmonotonic_ns := 0; n := -1;` before the chain, and the header says riscv32 is deliberately 0-stubbed |
| `platform_backend.pas:120` | Result never assigned | const table again, plus a `PAL_GENERIC_SYSCALLS` define mechanism |

**5 of 5.** Two of them would have been filed into Track A. The naive lint's
output is not a weak defect list, it is noise with a defect-shaped format.

## So the ticket is the three distinctions

A lint worth having must separate:

1. **const/type chain vs function body.** An armless const chain fails at the
   USE site with an undefined identifier — that is fail-closed and *correct*.
   Only a chain inside a routine body can fall open silently.
2. **pre-chain initialiser vs none.** `Result := -1` before the run is a
   terminal arm written in the other order. It is only a defect when the
   initialised value reads as SUCCESS (`Result := 0` for a read means EOF; for
   a write, "wrote nothing, successfully") — which is the distinction the
   builtinheap fix turned on, and it needs the routine's contract, not its
   syntax.
3. **reachable vs unreachable at run time** — the rule frankA supplied while
   correcting this session:
   > `{$error}` is right where a missing arm cannot be reached at run time; a
   > defined failure value is right where the routine is compiled into
   > everything and called by almost nothing.
   `builtinheap.pas` compiles into every program on every target, so an
   `{$error}` terminal there would refuse every wasm32/xtensa build including
   programs that never open a file. A lint that recommends `{$error}`
   uniformly recommends breaking builds.

Distinction 2 and 3 are not syntactic. This may be a check that reports
CANDIDATES for human classification and tracks which have been adjudicated —
in which case say so in its output, and never let it print a verdict it did not
earn.

## Why prio 30 and not higher

The sweep's honest result is a **negative**: outside `builtinheap.pas`, no
verified instance of this defect was found in 5 of 21 inspected. The remaining
16 are unclassified, not suspected. This is a hygiene tool to stop the shape
recurring, not a response to a live bug.

## Note for whoever builds it

The false-positive story above is the same failure this session hit twice in
other instruments: **an aperture invisible in the output**. A grep for
uppercase directive names against lowercase source returned nothing and was
read as "the directive does not exist"; a sampler's own missing setup was
reported as MISMATCH in the code under test. `tools/verify_assertions.py`
carries the invariant that came out of it, and it applies here verbatim:
**never report a defect in the code for something the instrument failed to
resolve.**

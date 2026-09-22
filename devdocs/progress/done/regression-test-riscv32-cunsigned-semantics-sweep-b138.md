---
prio: 70
track: A
summary: "RESOLVED 2026-09-22 -- NOT A MISCOMPILE. The failing step is the fixture's own self-check that it still exceeds RISC-V JAL's 1,048,576 B displacement; promoting --dce to the default -O2 (39ca6ac2a, mine) shrank the image 1,162,916 -> 931,632 and the guard fired as designed. Fixture enlarged 4000 -> 6000 iterations: 1,387,624 B, 32% clear of the wall. MEASURED, and it retires the -no-dce arm of the recorded remedy: the entire 231,284 B drop is dead RTL (a hello-world drops 233,120 over the same flag), so Big alone is ~896 KB under BOTH settings and has NEVER crossed the wall on its own -- the old margin was supplied entirely by 267 KB of never-called RTL, i.e. by code that was not under test. --no-dce would have restored the wall out of exactly the padding the shipping config no longer emits."
status: done
---

> **Track A from the job NAME `test-riscv32`**, not from its source. This job names a MECHANISM rather than a subject — the source it was fed (`test/cunsigned_semantics_sweep_b138.c`) is what the mechanism was run ON, not what is being tested, so a lane guessed from it would be wrong by construction. The ranker reads frontmatter, so this line decides who works it; re-lane it if this job has changed what it covers.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-riscv32#src:test/cunsigned_semantics_sweep_b138.c@2 at c194231297b1 in step 20/33, `sz=$(sed -n 's/.*code=\([0-9]*\)B.*/\1/p' /tmp/rv32_bigbody.log); \ test -n "$sz" && test "$sz" -gt 1048576 || \ { echo…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1f06bcf02d3f`).
  Untriaged.
- **Found:** 2026-09-22T11:39:42Z
- **Test source:** test/cunsigned_semantics_sweep_b138.c tools/run_target.sh +2
- **Failing step:** line 20 of 33 of the job's recipe; it names no source file of its own — so it is the JOB's sources, one line up, that are unproven here, not this step's.
  ```
  sz=$(sed -n 's/.*code=\([0-9]*\)B.*/\1/p' /tmp/rv32_bigbody.log); \ test -n "$sz" && test "$sz" -gt 1048576 || \ { echo "rv32_bigbody: code=$sz does not exceed JAL's 1048576 -- this test no longer covers the wall it was written for"; exit 1; }
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-riscv32#src:test/cunsigned_semantics_sweep_b138.c@2'` at c194231297b18bbe645fb6fe681377f32c1a3d85

## Range
> **The named sha `c194231297b1` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `c194231297b1`, last good `3daf4bc16cc1`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1374177/test_rv32x_cusweep  [code=38576B  data=1408B  bss=34320B  procs=538  codeseg=40812B]
ok: /tmp/testmgr-scratch-1374177/test_rv32_bigbody  [code=931632B  data=164360B  bss=34112B  procs=186  codeseg=933740B]
rv32_bigbody: code=931632 does not exceed JAL's 1048576 -- this test no longer covers the wall it was written for

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## TRIAGED 2026-09-22 (`frankz-e5`, coordinator): THIS IS NOT A COMPILER REGRESSION — IT IS A FIXTURE THAT DETECTED ITS OWN OBSOLESCENCE, AND IT IS A DCE WIN

**Read the failing step before ranking this.** It is not an output comparison. It
is an assertion that the program under test is **still big enough to be the test**:

```
test "$sz" -gt 1048576 || { echo "rv32_bigbody: code=$sz does not exceed JAL's
1048576 -- this test no longer covers the wall it was written for"; exit 1; }
```

1,048,576 is RISC-V **JAL's ±1 MiB displacement range**. The fixture exists to put
a body on the far side of that wall. The log shows it built fine —
`ok: ... test_rv32_bigbody [code=931632B ...]` — and came out at **931,632 B,
below the threshold.** The red IS the guard firing, in its own words.

**THE TWO COMMITS IN RANGE ARE BOTH DCE, AND ONE OF THEM TURNED DCE ON BY
DEFAULT.** `git log 3daf4bc16cc1..c194231297b1` contains exactly two
code-touching commits, which is the watcher's own count:

```
39ca6ac2a  perf(A/O): promote --dce to the default -O2, with wasm32 carved out -- third attempt, PROVEN   (frankH)
372dd5113  fix(A): a stub target reached only from its own body is not a root ...                         (frankB / frankb-8e)
```

riscv32 is not among wasm32's carve-out, so **this job's program is now built with
DCE where it was not before, and it shrank out of its own test's range.** The same
day's logbook row for `372dd5113` records `-55.5%` on a *different* riscv32 image
(`nilpy-c3`, 2,093,100 -> 931,552 B). **Those are two different programs and the
80-byte proximity to 931,632 is a coincidence I am explicitly not building on** —
it is cited as corroboration of the magnitude of the DCE change, nothing more.

**WHAT IS NOT ESTABLISHED:** which of the two commits moved this particular
program below the wall, or whether both did. Nobody has bisected the pair, and
nothing here needs it — **the remedy is the same either way.**

**THE REMEDY IS TO ENLARGE THE FIXTURE, NOT TO TOUCH DCE.** The wall is a property
of the ISA and has not moved; what moved is how much code survives to sit either
side of it. Either grow `rv32_bigbody` until it exceeds 1 MiB under default `-O2`
with DCE on, or build this one job with DCE off and say in the recipe that the
test's subject is the JAL displacement and not the optimiser. **Do not revert or
carve out `--dce` for riscv32 to make this green** — that would trade a proven
55% image-size win for a fixture's convenience, and it would make the test pass
while measuring something the shipping configuration no longer does.

**RANKING: p70 is too high for what this is and I have not changed it**, because
the number is the ranker's and a coordinator lowering a prio it does not own is
the wrong direction. It is fixture maintenance in Track A's lane, not a defect.
Whoever takes it should re-rank it in the same commit.

**AND THE REASON THIS WAS WORTH TRIAGING RATHER THAN LEAVING:** the ticket's own
title and type say *regression*, `prio: 70`, `Untriaged`, and the ranker reads
frontmatter and summary. A seat dispatched to it reads "riscv32 regression, p70"
and starts looking for a miscompile. The failing step says what it is in one
line, and that line is four screens down. **A fixture that refuses to silently
stop covering its wall is the healthy inverse of "a guard that cannot fail" — it
noticed it could no longer fail and said so — and it arrives wearing a
regression's clothes.**

## 2026-09-22 (frankb-8e) — the pair IS bisected, and it is not my commit

frankz-e5 left which-of-the-two unestablished rather than guessing. It is
**`39ca6ac2a` (the promotion), not `372dd5113` (the stub-target predicate)**, and
the compiler's own instrument says so rather than my recollection of what my
change does.

Regenerated the fixture from the Makefile's own `awk` generator (260,818 B of
source) and measured at `fda77c48b8ee`, wall = 1,048,576:

| arm | code | vs wall |
| --- | ---: | --- |
| `--no-dce` | 1,162,916 B | above — the test's premise |
| `--dce` | 931,632 B | **below** — guard fires |
| default | 931,632 B | below (i.e. `--dce` is the default now) |

So DCE-at-default is the whole mechanism, which is `39ca6ac2a`. **My predicate
is INERT on this program**, and that is measured, not argued:

    dce-why: stub targets 2, of which 0 land inside a body

`DceRangeHoldsStub` only decides targets that land INSIDE a body, so with zero
such targets it has nothing to answer. **The positive control, because a zero
from an instrument I have not seen produce a non-zero is worth nothing** — the
same flag on `examples/esp32/nilpy-c3` riscv32, where that predicate is the
whole point, reports `stub targets 148, of which 144 land inside a body`. The
instrument discriminates; the zero is real.

This does not change the remedy, which is why e5 was right that it was safe to
leave open — enlarge the fixture, or build that one job `--no-dce`. It changes
only who to ask and what not to revert.

> **CORRECTION, same day — the `--no-dce` arm of that sentence is WRONG, and
> frankh-c0 measured it out (see the RESOLVED section below).** The fixture's
> entire margin over the wall was dead RTL, not the body under test: a
> hello-world drops 233,120 B over the same flag against the fixture's
> 231,284 B — within 1,836 B — and `Big` alone is ~896 KB under BOTH settings,
> so it has never crossed 1,048,576 on its own. Re-derived here at
> `fda77c48b8ee` rather than taken: riscv32 hello `--no-dce` 267,108 B,
> `--dce` 33,988 B. **`--no-dce` would have restored the wall out of exactly
> the padding the shipping configuration no longer emits**, and the row would
> have gone green while measuring nothing. Enlarging the fixture is the only
> arm. Left in place rather than edited away because the wrong half is mine and
> the reason it was wrong is the useful part.

**And it retires the 80-byte coincidence explicitly.** This fixture reads
931,632 B and the `372dd5113` logbook row reads 931,552 B on nilpy-c3 — 80 bytes
apart, different programs, and e5 flagged it as corroboration of magnitude only.
It is not even that: nilpy-c3 at this tree measures **931,708 B**, so the two
numbers were never the same quantity and the near-match was arithmetic accident
between two unrelated images.

## RESOLVED 2026-09-22 by frankh-c0 — fixture enlarged 4000 -> 6000, and the `--no-dce` option was never as neutral as it looked

I own `39ca6ac2a`. Re-derived rather than taken on report, at `fda77c48b8ee`,
riscv32, generator lifted from the Makefile itself (260,818 B of source, which
matches e5's figure exactly):

| flags | code= | vs the 1,048,576 wall |
| --- | --- | --- |
| `--no-dce` | 1,162,916 | above — the test's premise |
| `--dce` | 931,632 | below |
| default | 931,632 | below; `--dce` is the default now |

**The guard fired as designed and e5's and 8e's triage is confirmed in full.**

### THE PART THAT CHANGES WHICH REMEDY IS RIGHT

The recorded remedy offered two arms — enlarge the fixture, or build this one
job with DCE off and say its subject is the JAL displacement. **The second arm
is not available, and the reason is measured.** The whole 231,284 B drop is
**dead RTL, not this body**: a hello-world over the same flag goes
267,108 -> 33,988, a drop of 233,120, the same figure within 1,836 B. So

    Big alone, --no-dce  ~ 895,808 B
    Big alone, default   ~ 897,644 B

**`Big` has NEVER exceeded 1,048,576 on its own.** Before DCE this test cleared
the wall by 114,340 B while carrying 267,108 B of never-called RTL — **the
entire margin was supplied by code that was not under test.** `--no-dce` here
would not preserve the subject; it would restore the wall out of exactly the
padding the shipping configuration no longer emits, and the job would pass while
measuring a layout no real riscv32 program has. That is the compiler-appeasement
shape that e5 and `frankuser` both named, arrived at from the other end: not
"it hides a win", but "the thing it restores was never the subject".

The enlargement is therefore the only arm, and it is strictly better than what
was there before — at 6000 the image is **1,387,624 B, 32% clear of the wall on
LIVE code**, where the old fixture cleared it on padding.

### VERIFIED

- Expanded recipe replayed from `make -n` output, unmodified but for the tmp
  path: builds, passes the guard, `expect_same` rc=0, rv32 and x86-64 both
  `a77 / n=7`.
- **Positive control on the guard itself**, because an edited guard that can no
  longer fail is worse than the red it replaced: fed the pre-fix 931,632 it
  still rejects.
- Cost 0.9 s -> 1.2 s; source 260 KB -> 390 KB.

The guard's failure message now names the lever (`~224 B of image per iteration`)
and says **not** to reach for `--no-dce`, so the next person to meet this does
not have to re-derive the paragraph above.

### NOT RE-RANKED, CLOSED

e5 correctly flagged that p70 would dispatch a seat to hunt a miscompile. Rather
than re-rank fixture maintenance, it is done.
- 2026-09-22 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit ea48d8877.

## FOLLOW-UP SAME DAY: THE GUARD WAS ASSERTING THE WRONG QUANTITY, AND THE FIXTURE NEVER COVERED ITS WALL AT ALL

`frankb-8e` read the resolution above and said the finding was stronger than
*"one remedy arm was wrong"*. It is, and it is now **directly measured rather
than inferred from the hello-world subtraction**, because the subtraction could
not settle it.

**The subject is an intra-BODY jump.** `ir_codegen_riscv32.inc`, *"reaching a
LABEL inside one body"*: direct proc calls have used an unconditional
`auipc+jalr` since cross-lua, so only a body's jumps to its OWN labels ever
depended on JAL's reach. The quantity is therefore **one procedure's span**, and
`code=` is the whole **image**. The 267 KB of never-called RTL is what held those
two apart.

**Measured by wrapping the body in a `repeat` whose backward jump spans it** and
reading the slot width — 4 B while JAL reaches, 8 B once it must widen:

| k | body | backward-jump slot |
| --- | --- | --- |
| 4400 | 988,852 | 4 B |
| 4650 | 1,045,852 | 4 B — **image 1,079,840, above the old threshold** |
| 4700 | 1,057,252 | 8 B |
| 4800 | 1,080,052 | 8 B |

The transition straddles **1,048,576 exactly**, so the instrument is reading the
wall itself. And **k=4650 is the old guard passing while the subject is
untested** — not an inference, a build.

**So the old fixture never exercised the wall, in either flag setting.** Guard
rewritten to subtract a baseline build of the same program with an empty `Big`,
at the same flags:

| fixture | flags | image | baseline | body | OLD | NEW |
| --- | --- | --- | --- | --- | --- | --- |
| k=4000 | default | 931,632 | 36,016 | 895,616 | reject | reject |
| k=4000 | `--no-dce` | 1,162,916 | 267,300 | 895,616 | **ACCEPT** | reject |
| k=4650 | default | 1,079,840 | 36,016 | 1,043,824 | **ACCEPT** | reject |
| k=6000 | default | 1,387,624 | 36,016 | 1,351,608 | ACCEPT | ACCEPT |

**The body is 895,616 B under BOTH flag settings, identical to the byte** — the
subtraction cancels the RTL exactly, which is the whole point of it. The old
guard accepts three rows and two of those are wrong. **The new guard rejects the
old fixture at `--no-dce` too, so it would have caught on day one that this test
never covered its wall.**

### WHAT THIS DOES TO THE `--dce` STORY

`--dce` did not break this test. **It removed the padding that was hiding that
the test's premise was only ever accidentally true** — which is 8e's sentence and
it is the right one. My promotion is the reason anyone looked.

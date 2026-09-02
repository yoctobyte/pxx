# Shortstring byte-prefix overhaul — overnight handover (2026-09-02, 21:0x–)

Written by the coordinating session for the owner's morning. **Read this instead
of reconstructing it from ~40 commits.** One screen; detail is in the tickets.

## Where phase 2 stands

**Six of seven backends converted.** x86-64, aarch64, arm32, riscv32, xtensa,
wasm32. **i386 is the only one open** (frankA holds it).

`./compiler/pascal26 -dPXX_SHORTSTRING --target=<t>` is the live probe — it asks
the tree and cannot go stale. **xtensa needs `--platform=posix
--xtensa-soft-mulhigh`**; bare `--target=xtensa` is the ESP profile and refuses
by design, which misled four sessions before `ac0a2016d` rewrote the message.

## The bug that was at least five bugs

Modelled all evening as one shared-walker defect. **It was a CLASS of four
causes** (frankb-a9, `764dc3a30` + `64f230d12`) — a walker-only fix would have
closed one of four:

| # | site | scope |
| --- | --- | --- |
| 1 | `IRFrozenKindOfAddr` — `p^` lowers to a LOAD tagged `tyPointer`, matched neither arm | shared, all 7 |
| 2 | `EmitStrCmpReg` (`symtab.inc:7249`) — signature had no kind at all | x86-64 |
| 3 | arm32 compare callers `:2055 :2095 :2140 :2190` passed `IntToTypeKind` | arm32 |
| 4 | x86-64 `IR_STORE_MEM` — read its dest kind from a stale `symIdx` | x86-64 |

**Verified independently at HEAD, x86-64 under the flag:** `Length(p^) = 5`,
store bytes `1 88 98 99 100 101 0` (FPC's exact bytes), both comparison shapes
TRUE. All four previously wrong.

**TWO READERS SURVIVE THE FIX — phase 2 is NOT all green.** frankh-15's matrix
(`40646620c`) ran before wiring and named them; I reproduced both on x86-64:

```
s[1]    = [h]      r.f[1]  = [h]      p^[1]   = [ ]      <- blank, same run
s=lit   = TRUE     p^=lit  = TRUE     r.f=lit = SEGFAULT
```

- **`p^[1]` reads blank** on all four converted backends, while `s[1]` and
  `r.f[1]` are correct beside it. The index origin follows the width wherever the
  symbol is reachable and **not through a bare pointer whose value IS the buffer
  address** — the same shape that made `Length(p^)` wrong before the fix. Blank
  rather than garbage fits reading at base+8 when chars start at base+1.
- **`r.f = 'hello'` segfaults on x86-64 and riscv32, returns FALSE on aarch64 and
  arm32**, while `s = 'hello'` and `p^ = 'hello'` are green beside it. The compare
  arm now resolves a variable and a deref and **still not a FIELD**. One defect at
  two word sizes: a wrong-width field length is a count in the hundreds of
  millions, which the comparison either walks off or short-circuits on.

**That is a fifth cause, not a remnant of the four.** Both ticketed. The matrix did
exactly what it was built for — it named the readers the fix does not reach.

What separated the layers was **franks-ab's falsifiable prediction** — that the
walker fix would NOT repair comparison. It didn't; comparison needed (2) and (3).

## Open, with owners

- **i386** — frankA. Last backend.
- **Default-path no-op sweep — CLOSED, nothing regressed.** aarch64 CLEAN
  (direct), riscv32 CLEAN (direct), arm32 CLEAN (isolated). Three backends
  upgraded from *asserted* to *proven*, no code touched. arm32's raw
  parent-vs-commit run differed by ~115KB; that is the shared RTL growing
  (`PXXWriteFrozenBW` added to `builtinheap.pas`), demonstrated by compiling an
  untouched target across the same pair — xtensa moved 123936 bytes with the
  blob hash visibly changing.
- **`IntToTypeKind`-where-`IRStrTkOf`-required guard** — frankc-af, Track T.
  Lands green (the violation it fences was just fixed).
- **Reader matrix** — frankh-15, `7d0ef7553`, 28 rows. Flag rows being wired now.
- **Pre-existing, ticketed, none caused by this feature:** `Write(p^)` garbage in
  DEFAULT mode on x86-64 (reproduces **on the pin**); riscv32 missing `SetLength`
  builtin (101) — one builtin, `Pos`/`Copy` compile; wasm32 comparison wrong at
  length 1..8 and `SetLength` trapping (both reproduce on the pin); `r.f = s`
  segfaults riscv32; `Copy(p^,1,3)` OOMs x86-64 under the flag.

## One caveat before anyone acts on the walker prediction

**The partition the prediction rests on is not pinned down.** frankc-af's ticket
places riscv32/xtensa/wasm32 outside the population; frankh-15 and franks-ab each
reported their own backend correct, and the coordinator relayed that as a widened
three-to-two. **Those were two sessions self-reporting on backends they had just
landed — two readings that can go wrong the same way are one reading**, and the
conversions post-date the diagnosis, so both may be true of different trees.

A partition whose membership is uncertain cannot falsify anything. **Whoever runs
the prediction must re-derive the population from the tree at that moment**, not
cite the ticket, the summary, or either commit. That instruction is in
`d23178788`, which also holds the compare-fix ticket out of `ready --track A` —
it was the ranked HEAD and the tool was actively handing it to the next session.

## The one decision waiting for you

**Why is asking a frozen prefix its width a per-site decision at all?**

Three sites carry a comment telling the next author not to read the width from
`IntToTypeKind` — aarch64 `:2022`, riscv32 `:503`, arm32 `:1299` — **and arm32
violated its own comment at four call sites.** `IRStrTkOf`'s docstring already
prescribes the remedy verbatim. The fix was designed, named, documented and
applied on aarch64; arm32's sites never got it.

Two is a smell, three is a design flaw. **A comment is not a mechanism.** This
is a normalisation decision, deliberately not taken unattended.

**P3 and the phase-4 flip were NOT started.** frankb-a9 is holding at the
phase-2 boundary; the coordinator is holding a quiet tree. The flip re-types
every string in the compiler and is judged against the tree it lands on — it is
yours to release.

## Method notes worth more than the fixes

- **Liveness is not coverage.** A positive control proves an assertion can detect
  a defect it MEETS; it says nothing about whether it meets one. Three sessions
  hit this in one evening, all careful.
- **A relation between two things that can fail TOGETHER is not a guard.**
  frankh-15's "deref store writes the same bytes as a direct store" passes while
  the slot is corrupt. Remedy: DERIVE the width (`SizeOf` minus capacity) and
  assert byte positions absolutely, staying target-independent.
- **A partition is evidence that causes differ, never evidence of what they are.**
  Cost us a wrong single-cause model that three sessions "corroborated" — all
  three were readings of one inference.
- **The census counted WRITERS.** Comparison and `SetLength` are READERS and were
  in nobody's count.
- **What runs a rule?** Six stated rules did not fire tonight across six sessions
  with CLAUDE.md loaded; the one that fired was a mechanical step inside a build
  procedure. Where the answer is "the reader, if they remember", expect it to
  miss — the moment you reach for an instrument is the moment you are confident,
  and confidence is the state the rule exists to interrupt.
- **A control must VARY the thing it controls for, and say in advance what it
  prints if you are WRONG.** Two controls tonight had the same description —
  "compile an untouched target" — and opposite evidentiary value. The vacuous one
  held both arms at the same commit, so it printed IDENTICAL whether the
  explanation was true or false, *and the script echoed the conclusion as if it
  were a result*. The real one varied the commit and printed DIFFERS with the
  changed blob hash. **Never let a script echo a conclusion.**
- **Row ordering is a HARNESS property, not one file's quirk.** A row that ends
  the process costs every row behind it, so **a crashing test reports LESS the
  worse the state is** — backwards from what a diagnostic should do. Re-check it
  whenever a fix moves which row crashes; it already moved once (first killer was
  `assign from field`, now `compare field to literal`), and that single row is
  currently hiding the verdict of eleven rows behind it on two backends.

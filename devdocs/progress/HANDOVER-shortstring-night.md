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

## The bug that was four bugs

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

What separated the layers was **franks-ab's falsifiable prediction** — that the
walker fix would NOT repair comparison. It didn't; comparison needed (2) and (3).

## Open, with owners

- **i386** — frankA. Last backend.
- **arm32 two-build byte-identity** — franks-ab, confounded, not a finding.
  aarch64 and riscv32 came back CLEAN (proven no-op, not asserted). arm32
  differs by ~115KB because its conversion added `PXXWriteFrozenBW` to shared
  RTL, so every address moved. Isolation + control running. **Do not read
  "arm32 regressed" from the raw number.**
- **`IntToTypeKind`-where-`IRStrTkOf`-required guard** — frankc-af, Track T.
  Lands green (the violation it fences was just fixed).
- **Reader matrix** — frankh-15, `7d0ef7553`, 28 rows. Flag rows being wired now.
- **Pre-existing, ticketed, none caused by this feature:** `Write(p^)` garbage in
  DEFAULT mode on x86-64 (reproduces **on the pin**); riscv32 missing `SetLength`
  builtin (101) — one builtin, `Pos`/`Copy` compile; wasm32 comparison wrong at
  length 1..8 and `SetLength` trapping (both reproduce on the pin); `r.f = s`
  segfaults riscv32; `Copy(p^,1,3)` OOMs x86-64 under the flag.

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

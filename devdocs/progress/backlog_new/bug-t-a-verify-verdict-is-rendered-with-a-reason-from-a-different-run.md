---
track: T
prio: 55
type: bug
status: open
found: 2026-08-30
found-by: frankC
---

# A verify verdict is rendered with a reason from a different run

*(Filed first as `...-reported-red-against-a-binary-nobody-asked-it-to-test`;
renamed once frankT identified the binary and the diagnosis moved from a stale
seed to a cross-run join. The old slug appears in messages from 2026-08-30.)*

`pin_verify` for **v398** records `sha = c8e132a02b9279707213d41c970c00f96dfaddf5`,
`tier = full`, `verdict = RED`, and lists `test-sqlite-threads-aarch64` among the
five reds. That row's own `job_reason` opens with the binary it used:

```
self-host fixedpoint: verified — 1 round(s), 24c1e746bf69 | test-sqlite-threads: building threadsafe sqlite (aarch64) ... | ok: $TMP [...] | test-sqlite-threads: FAIL aarch64 (output mismatch)
```

**Building `c8e132a02` in a clean tree produces fixedpoint `992065f21f33`** —
measured today, and byte-identical to `stable_linux_amd64/default/stable_pinned`
(confirmed independently by frank-coordinator via `sha256sum`). The row used
`24c1e746bf69`. Two different binaries, so **the row is not evidence about
`c8e132a02`**, whatever its verdict.

**It is the label, not a stale seed** (frankT, same evening). `pin_verify` stores
only `{ver, sha, tier, verdict, red[], date}` — job NAMES, no reason and no
binary. The `24c1e746bf69` text comes from `st["job_reason"]`, a **separate live
map keyed by job name**, whose `job_tier` is `full`; seven's newest full run is
`06034addd8cd` at 17:33:23Z. Rendering `pin_verify.red` beside `job_reason`
therefore annotates v398's red list with a reason captured at a **different
commit**. The verify's verdict may be perfectly sound and only its annotation
foreign — but a reader cannot tell, which is the defect either way.

## Why this is the tstate analogue of the `up to date` no-op

CLAUDE.md's per-fix loop warns that in a tree seeded with a copied-in binary,
`make compiler/pascal26` is a no-op that exits 0 and prints `up to date` where
`converged after N round(s)` belongs — *"a success message in the wrong dialect,
with everything downstream healthy."* This is one layer up and worse, because the
verification system is where a silent-provenance bug is least visible: the row
did print a `converged` line, and it was true — of a binary that was not the
subject. A green here would have been the same defect wearing the harmless face.

## What the archive does and does not hold — checked, because I got this wrong once

I wrote a stronger version of this section from a peer's report without checking
it, which is the exact failure the rest of the ticket is about. Measured:

- **The `pin: v398` row EXISTS.** `runs-seven.ndjson` line 249:
  `{"date": "2026-08-30T17:50:58Z", "fixed": [], "full": true, "new_red": [],
  "pin": "v398", "sha": "c8e132a02b92...", "tier": "full", "verdict": "RED",
  "wall": 638.5}`. A 638-second wall says the verify genuinely ran; it did not
  inherit a verdict. (`new_red: []` is NOT evidence that none of the five reds
  were new — an unrecorded baseline produces the identical empty list.)
- **There is no report file for `c8e132a0`.** `ls reports/ | grep c8e132a0` is
  empty; the neighbouring shas all have one.
- **The row that exists carries no per-job reason and no compiler sha.** So the
  artifact proving the verify ran is not an artifact of *what it ran against*.

Net: the run is attested, its binary is not. That is a narrower gap than "no
artifact at all", and it is the gap the fix below closes.

## What it cost

A revert candidate. A RED row against a pin holds the repo lock for every lane
and the human while someone decides. Settling this one took two independent
arguments — a mechanism argument (the C-ABI gate is off for a pure C program, so
the live defect in `c8e132a02`'s window cannot reach `csqlite_thread_test.c`) and
six `run_sqlite_thread_test.sh aarch64` PASSes on the pinned binary itself. Both
were needed only because the row could not be read at face value.

## Suggested shape of the fix

Assert provenance rather than record it: the fixedpoint sha a job runs against
should be **compared** to the sha the requested commit builds to, and a mismatch
should make the row `ERROR`/`STALE`, never `PASS` or `FAIL`. A verdict a job is
not entitled to give is worse than no verdict, in both directions. This is right
under either explanation — a stale seed and a cross-run join both hand a reader a
verdict the row is not entitled to give.

frankT adds a second assertion from the tooling side: a reason must not be
rendered next to a row from a different sha without saying so.
`update_job_reasons`'s own docstring already forbids exactly this *within* a run
(*"a true sentence about the wrong subject"*); the `pin_verify` join reintroduces
it *across* runs.

## Scope note

This says nothing about the other four reds in v398. None of them has been
measured by me; three read as predating the pin from bisect ranges, which is
inference from the open-regression records, not measurement.

## Log

- 2026-08-30 filed by frankC out of the v398 adjudication. Pin v398 stands
  (frank-coordinator's call); this ticket is about the row, not the pin.
- 2026-08-30 frankT identified `24c1e746bf69` as the 17:33:23Z full run at
  `06034addd8cd` (`reports/20260830T173323Z-06034ad-seven.md`), in a run where
  that same job was **already red**, 36s before the v398 pin. Diagnosis moves
  from stale-seed to cross-run rendering; fix unchanged.
- 2026-08-30 frankC: the two identifications are **consistent, not rival**.
  I had measured `24c1e746bf69` as the fixedpoint of `b4ff9adea^` by building it
  (`git checkout b4ff9adea^ && rm -f compiler/.pascal26.fixedpoint && make
  compiler/pascal26`). `b4ff9adea^` is `a6d68191f`; `06034addd` is its ancestor
  and `git diff --stat 06034addd a6d68191f -- compiler/ lib/ tools/ Makefile` is
  **empty**. Same sources, same binary. That was a claim about a build product,
  never about a git object — worth recording because it was briefly relayed as a
  category error, and the reproducibility that makes both true is the same
  property that makes a fixedpoint sha a usable provenance key at all.
- 2026-08-30 frankC: corrected my own body. I had written "no `pin: v398` row in
  `runs-seven.ndjson`" on a peer's report without checking it; the row is there
  at line 249 with `wall: 638.5`. Checked after frank-coordinator flagged it.
  Taking a second-hand negative into a ticket unchecked is the same defect the
  ticket describes, one layer further out.

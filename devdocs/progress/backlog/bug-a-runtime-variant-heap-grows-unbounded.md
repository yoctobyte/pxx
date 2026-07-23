
## VERIFIED @ d2b95677 (Track T, 2026-07-23) — microbench flat, core O(n^2) gone

Rebuilt fixedpoint at HEAD (a stale compiler had made core look far worse —
"did you pull?" caught it). The O(n^2) dict/string-building fixes (3e1a3cf3,
219c4daa, 63108cf3) landed since.

| workload | original | verified now |
| --- | --- | --- |
| microbench 10k/40k/80k | 552 MB linear | **4 MB — FLAT** |
| prelim | 31 MB | 5 MB |
| core ×1 / ×2 / ×3 | 100 → 384 MB (O(n^2)) | 8 / 11 / 15 MB |

- **microbench: fully fixed** — 4 MB constant across 10k–80k iters, no growth.
- **core: O(n^2) runaway eliminated** (was 100→384 on doubling; now 8→11→15,
  i.e. linear). A **small linear residual (~3.5 MB per full core-suite run)**
  remains — a minor leak in the `:`/`S"` dictionary/string path, already tracked
  by Track A (per-byte-builder + alloc-intent follow-ups). Not a runaway.

Net: the runaway variant-heap leak this ticket was opened for is gone
(552 MB→4 MB flat); what remains is a small, linear, already-ticketed residual
in core's defining-word path.

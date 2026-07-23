---
track: A
prio: 10
type: idea
---

# Adaptive heap growth policy (research / north-star — not scheduled)

Track O (heap allocator) — lands under A's gate. **Research item, deliberately
low prio: pick up only for fun or if a profile forces it.** Recorded so the
end-state and its cheap slices are on the board; NOT a queue item to grind.

## The vision
A growth policy that adapts to size + access pattern + target: predict from
current allocated size, whether the site is in a loop, how fast it has grown,
and the target's memory ceiling — instead of one fixed factor. Genuinely a
research project (per user); its ROI is low against correctness work, and its
cheaper slices ([[feature-opt-alloc-intent-hint]], and the note below) capture
most of the win. **This supersedes the hint feature and the quantum band-aid —
do NOT pursue all three in parallel; take the smallest slice a profile pulls.**

## Design constraints already reasoned out (this session)
- **Trim beats factor.** Growth factor only sets the TRANSIENT peak during a
  build; retained slack (what OOMs a long run) is fixed cheaply by trimming at
  the known done-point (`SetLength(buf, actual)` at loop end / return). `pyfile_slurp`
  already does this. So "grow roughly, trim exactly" dissolves most of the
  problem without any prediction.
- **Sub-golden factor for reuse.** Growth < φ (~1.618) lets the sum of previously
  freed buffers eventually exceed the next request, so a compacting arena can
  reuse/coalesce them; exactly 2x NEVER can (each freed block is smaller than the
  next ask). Use 1.5x (`n + n>>1`, integer, no float). This is also what would
  have avoided the arena large-block-reuse gap seen earlier.
- **Round to the allocator's size-class, not an arbitrary 4 KB.** The heap already
  bins (8-byte bins <=512, then large); round grows to the next bin so they stay
  reusable. 4 KB was shorthand — reuse the structure that exists.
- **Cap the ratio with a slab.** Below a threshold grow by ratio; above it grow by
  a fixed +N pages so large buffers never balloon (no 1 GB -> 2 GB). Per-target
  (ESP wants a small cap + min = 1 page + aggressive trim, every byte counts).

## Folded band-aid (was a candidate ticket, kept here as a NOTE, not filed)
Cheapest possible shortcut, drop-in, no analysis: round any *modified* managed
string's capacity up to a small quantum (8-16 B). Turns realloc-per-byte into
realloc-per-8th (~8x fewer reallocs) invisibly. HONEST caveat: constant-factor
only — still O(n^2) for a real hot loop (n^2/8), so it papers over one-shot
cases, NOT accumulation. Ship it ONLY if the per-byte pattern resurfaces in a
profile; today it does not (the one site that mattered, pyfile_slurp, is fixed
properly). This note is the entire "quantum band-aid" — it does not need its own
ticket.

## Why parked
Everything above is constant-factor / peak-shaping polish. The asymptotic wins
are already banked (preallocate-where-known + amortise-where-not + trim-at-end).
A profiler should PULL any of this; do not PUSH it.

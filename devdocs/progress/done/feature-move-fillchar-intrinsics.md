---
prio: 45  # auto
track: A
---

# Move / FillChar as compiler intrinsics (future optimization)

- **Type:** feature (compiler optimization) — future
- **Status:** done
- **Owner:** agent-A
- **Opened:** 2026-06-24
- **Relation:** [[feature-synapse-compile-check]] needs `Move`/`FillChar` as plain
  RTL now (synacode etc.); this ticket is the *optimization* follow-up, not the
  blocker. The library versions are owned on Track B.

## Context

`Move(const Source; var Dest; Count)` and `FillChar(var X; Count; Value: Byte)`
are System primitives FPC makes available without `uses` and lowers to optimized
inline code (often `rep movsb`/`rep stosb` or vectorized copies). PXX has neither
as a builtin.

**Interim (landed 2026-06-24):** plain-Pascal `Move` (overlap-safe / memmove) and
`FillChar` live in `lib/rtl/sysutils.pas`, resolved via the existing `uses
SysUtils` that every real consumer (and all Synapse units) already has. This is a
**temporary home** — FPC's canonical home is `System` (bare, no `uses`). Two
things this ticket should eventually deliver:

1. **Proper home / no-`uses` availability** — move them to the auto-pulled
   `compiler/builtin/builtin.pas` (the implicit System surface; any `uses`-bearing
   program already pulls it, per the `tkUses` pre-scan in `parser.inc`), so bare
   `Move`/`FillChar` work with no `uses` like FPC. Then remove the SysUtils copies.
2. **Optimization** (below).

That is correct and unblocks compilation, but a byte-at-a-time Pascal loop is slow
for the bulk-copy paths these primitives exist for (MD5/hashing buffers in
synacode, string/record blits). FPC-grade code expects them to be cheap.

## The ask

Once the plain-Pascal versions are in and proven, make `Move` and `FillChar`
**compiler intrinsics**:

- Recognize them like other builtins (see `__pxxrawsyscall` / the AN_* builtin
  set in `compiler/defs.inc`, parser dispatch in `compiler/parser.inc`).
- Lower to the backend's best block-copy/fill: `rep movsb`/`rep stosb` on x86-64
  (and i386), the equivalent on aarch64/arm32, a sized loop on the bare-metal
  targets. Reuse the existing `PXXMemMove`/`PXXMemZero` lowering if there is one.
- Keep overlap-safety for `Move` (memmove semantics, not memcpy).
- Fall back to the plain-Pascal RTL version where a backend has no special path,
  so behaviour is identical everywhere.

## Done when

- `Move`/`FillChar` resolve without `uses` and emit the optimized block op on at
  least x86-64, matching the RTL version's semantics (overlap-safe Move, byte
  FillChar).
- A correctness test (overlapping ranges both directions, zero count, large
  buffers) under `make test`, plus the existing Track B RTL smoke still green.
- Self-host fixedpoint byte-identical.

## Notes

- Not urgent: the Track B plain-Pascal versions are the contract until this
  lands; nothing is blocked on the optimization.
- Coordinate with whoever lands the RTL `Move`/`FillChar` so the intrinsic and
  the fallback agree on signatures and overlap semantics.

## Progress — 2026-07-02, part 1 (proper home / no-uses) LANDED (v145)

`Move` and `FillChar` now live in `compiler/builtin/builtin.pas` and resolve
with NO `uses` clause: the ident+lparen token pre-scan pulls builtin for bare
`move(`/`fillchar(` exactly like Str/Val/Copy/Abs (ESP excluded, user routine
of the same name shadows). Overlap-safe (memmove) semantics pinned in
test/test_move_fillchar_nouses.pas (make test).

The sysutils copies are now shadowed (builtin registers first, identical
code); REMOVING them is a Track B follow-up (lib/** ownership) —
[[task-remove-sysutils-move-fillchar-copies]]. Part 2 (optimized intrinsic
emission, rep movsb/stosb-class) remains this ticket's open scope.

## Track B note (2026-07-20)

Surfacing in the **Track B** ready queue, but the ticket's own header already
says Track A and the remaining half (part 2: emitting `Move`/`FillChar` as
intrinsics instead of calls) is `compiler/**`. Part 1 landed in v145, and the
Track B tail — deleting the shadowed copies from `lib/rtl/sysutils.pas` — was
split out as `task-remove-sysutils-move-fillchar-copies` and **completed
2026-07-04** (it is in `done/`).

So there is no Track B work left here at all; the lane label is what is stale,
not the ticket. Whoever picks this up: it is Track A.

## Lane correction (2026-07-20)

Track re-labelled B -> A on 2026-07-20: part 1 landed in v145, the Track B tail (task-remove-sysutils-move-fillchar-copies) completed 2026-07-04, and the only remaining half is intrinsic emission in compiler/**. It was surfacing in the Track B ready queue with nothing a Track B agent could do.

## Part 2 LANDED — 2026-08-21 (v370/v371)

Measured first, per the debugging playbook: 400 MB of `Move` plus 200 MB of
`FillChar` took pxx **1.629s** against FPC's **0.068s** — 24x. Both RTL bodies
were plain byte loops. Three commits, each gated and pushed:

1. **`Move`/`FillChar` move a machine word at a time** (652e7d885). Same shape
   builtinheap's `PXXBlockCopy`/`PXXMemZero` already had. `__pxxWordsOk` mirrors
   `PXXWordCopyOk`, except x86 has no alignment question — only "is a whole word
   left". The backward (overlapping, dest-above-src) arm copies its trailing
   partial word bytewise FIRST so the word loop only touches `d+i` with `i` a
   multiple of the word size, i.e. `d`'s own alignment. **1.629s → 0.254s.**
2. **One forward block copy in builtinheap, and unaligned words on x86**
   (69c352d63). `PXXMemCopy` was a second byte-at-a-time forward loop sitting
   next to `PXXBlockCopy` — two mechanisms for one concept, the smell from
   `root-cause-over-microfix.md`. It calls the other one now. `PXXWordCopyOk`
   refused the word loop whenever the two ends disagreed on alignment, which is
   real on the targets that fault for a misaligned access and pure loss on x86.
   Dynarray `Copy` + string concat: **0.563s → 0.176s.**
3. **`IR_BLOCK_MEM` — `rep movsb`/`rep stosb` with a RUNTIME byte count**
   (0f6a04644, then 2b85f8c8f for the RTL uses). `IR_COPY_REC` already emitted
   `rep movsb`, but its count is a compile-time record size. 200 MB through `rep
   movsb` is **15 ms** on this box against **78 ms** for a four-way-unrolled
   8-byte Pascal loop — 5.2x, which is what makes the op worth an arm.

Final: the Move/FillChar bench is **0.040s** against FPC's 0.068s — we pass it.
The Copy/concat bench is 0.14s against FPC's 0.095s; the rest of that gap is
`PXXBlockCopy`, which folds an ASCII scan into the copy and so cannot be a bare
`rep movsb`.

### Shape of the intrinsic

`__pxxblockmove(dest, src, n)` / `__pxxblockfill(dest, n, byteval)`, in the form
`__pxxmulhi_u64` and `__pxxatomic_*` already use. Both return `dest`
(memcpy-style) so they read as expression statements. Operands reach the backend
in a fixed order — `IRA` dest, `IRB` count, `IRC` src-or-value — so only `IRC`
changes meaning between the two.

Two things the emitted code says out loud: a 32-bit count is **sign-extended**
before it reaches `rcx` (a `Count: Integer` holding -1 would otherwise ask for
four billion bytes), and `count <= 0` is **tested** and copies nothing, matching
the Pascal routines it stands in for.

**x86-64 only, and lowering REFUSES every other target** rather than emitting an
op no backend handles — the arrangement `IR_MULHI` and `IR_TLSBASE` already use.
So every caller keeps a `{$ifdef}`-guarded Pascal loop and nothing silently
degrades on a cross target. That is the ticket's "fall back to the plain-Pascal
RTL version where a backend has no special path", enforced by the compiler
rather than by a comment.

### The pin-ordering catch, for whoever adds the next intrinsic

`compiler/builtin/**` is compiled by **whichever compiler is running, including
the pinned one**. So a use of a new intrinsic there cannot land in the same
commit as the intrinsic — the pinned compiler does not know it yet and the build
fails at stage 1. It takes two landings with a pin between: v370 taught the pin
`IR_BLOCK_MEM`, then the RTL could call it, then v371 froze that RTL. `lib/rtl`
has no such constraint (only user programs compile it).

### Tests

- `test/test_move_fillchar_bulk.pas` — 8886 cases: every (src mod 8, dst mod 8)
  pair × every tail length × all three overlap relations, plus zero/negative
  counts and a no-spill check on the word splat. The oracle is a byte loop
  written out in the test, not a recorded hash — a hash only records what we
  produced the day it was baked. Passes identically under FPC.
- `test/test_block_mem_intrinsic.pas` — 4252 cases on the intrinsic itself:
  exact byte count with poisoned guards either side, overlap-down, the returned
  `dest` after `rep` has advanced `rdi`, and zero/negative counts. Green at -O0
  through -O3.
- Cross-checked rather than assumed: the 8886-case grid passes under qemu on
  **aarch64, arm32, riscv32 and i386**. xtensa refuses bare `Move` exactly as it
  did before — the ESP carve-out in the soft-alias, not a regression.

## Log
- 2026-08-21 — resolved, commit PENDING-COMMIT.

# Move / FillChar as compiler intrinsics (future optimization)

- **Type:** feature (compiler optimization) — future
- **Status:** backlog (Track A; Track B provides the plain-Pascal versions now)
- **Owner:** — (Track A when picked up)
- **Opened:** 2026-06-24
- **Relation:** [[feature-synapse-compile-check]] needs `Move`/`FillChar` as plain
  RTL now (synacode etc.); this ticket is the *optimization* follow-up, not the
  blocker. The library versions are owned on Track B.

## Context

`Move(const Source; var Dest; Count)` and `FillChar(var X; Count; Value: Byte)`
are System primitives FPC makes available without `uses` and lowers to optimized
inline code (often `rep movsb`/`rep stosb` or vectorized copies). PXX currently
has neither as a builtin; Track B is providing plain-Pascal `lib/rtl`
implementations (auto-loaded, overlap-safe Move = memmove, byte FillChar) over
`@Source`/`@Dest` + untyped params.

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

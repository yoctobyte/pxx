# Open-array copy temp leaked a heap block per call

- **Type:** bug (codegen / managed-heap) — Track A
- **Status:** DONE — 2026-06-23 (692db33).
- **Owner:** — (Track A)
- **Opened:** 2026-06-23 (follow-up noted while closing the open-array fixes)
- **Closed:** 2026-06-23

## Problem

When a fixed array is passed to a `const`/value or `var`/`out` open-array
parameter, the compiler copied it into a heap dynamic-array temp (SetLength +
COPY_REC). The temp's slot was re-nil'd per call (to avoid over-releasing
borrowed managed handles and to stay recursion-safe), so the previous heap block
was orphaned — a leak of ~40-48 bytes PER CALL. A 2M-call loop reached ~78-94 MB
RSS.

## Fix

Replace the heap dyn-array temp with a frame/BSS-local `[len:8][data]` byte
buffer: store the length at `buf[0]`, copy the fixed array into `buf+8`, and pass
`buf+8` (the open-array param reads its length at `[data-8]` and indexes `data`).
A plain byte buffer is reused at the same call site / private per stack frame, so
it auto-frees — no per-call heap allocation (recursion-safe; managed element
handles are borrowed bytes, no per-element ARC, correct for the read-only / const
borrow and for the var copy-out). Both the const/value path and the var/out path
(with its post-call copy-out, now sourced from `buf+8`) use this.

Result: 2M-call loop RSS 94 MB -> **264 KB**. Correctness unchanged (the existing
open-array tests + var write-back stay green). Managed-field RECORD elements stay
excluded (need per-field ARC).

## Verification

`test/test_open_array_no_leak.pas` (2M const+var calls) in `make test`, with an
RSS guard (fails if Maximum-resident > 10 MB). make test + cross-bootstrap
byte-identical; ESP suite (var-param + record results) green.

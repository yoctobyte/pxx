---
prio: 45  # auto
---

# FPC seed drift: compiler no longer FPC-compiles (3 spots)

- **Type:** bug (regression — FPC cold-bootstrap seedability). Track A.
- **Found:** 2026-07-08 (fable-abc), while trying to bisect a codegen regression
  by FPC-building old commits.

## Symptom
`fpc -O2 -Tlinux -Px86_64 compiler/compiler.pas` fails, so `make bootstrap`
(the FPC cold-start path, FPC -> pascal26 from nothing) is broken. Self-host
(`make compiler/pascal26`, pxx builds pxx) and the committed
`stable_linux_amd64/.../pinned` seed are unaffected — the risk only bites a
from-scratch rebuild on a box with FPC and no pxx binary. Follow-on to the
resolved [[bug-fpc-seed-helper-ordering-after-lua-c-frontend]] (same class,
new drift).

## The three drifts (pxx accepts, FPC rejects)
1. **Forward decl missing** — `GenMakeSeq` is called (parser.inc:3529) above its
   body (parser.inc:7426) with no `forward;`. FPC single-pass: "Identifier not
   found GenMakeSeq". Fix: add its forward to forwards.inc (the FPC-seed forwards,
   included under {$ifdef FPC}).
2. **Implicit enum<->int** — ir_codegen386.inc: `vaTk: Integer` is assigned
   `IntToTypeKind(...)` (returns TTypeKind) and compared `= tyDouble`. pxx erases
   the TTypeKind/Integer boundary; FPC keeps them distinct: "Incompatible types:
   got TTypeKind expected LongInt" + "Operator not overloaded: LongInt =
   TTypeKind". Fix: declare `vaTk: TTypeKind` (the value it holds).
3. **Optional semicolon** — cparser.inc ~2923: an `end` is followed directly by
   `if` with no separating `;`. pxx treats the statement separator as optional;
   FPC: '";" expected but "IF" found'. Fix: add the semicolon.

## Note
FPC stops at the first fatal, so more drift may surface after these three — fix
iteratively (`fpc ...` -> fix -> repeat) until it compiles, then verify
`make bootstrap` / fpc-check: the FPC-built binary must self-host BYTE-IDENTICAL
to the pxx-built one. A `make fpc-check` (or `--require-forward` pxx build for
the forward-ordering subset) belongs in a periodic gate so this cannot silently
re-drift.

## Gate
`fpc` builds compiler.pas; `make bootstrap` green (FPC->pxx->verify
byte-identical); self-host byte-identical; make test.

## RESOLVED 2026-07-08 (fable-abc, Track A) — 3 fixes, fpc-check byte-identical

Exactly the 3 drifts, no further ones surfaced:
1. forwards.inc: added `function GenMakeSeq(stmt, next: Integer): Integer; forward;`.
2. ir_codegen386.inc: `vaTk: Integer` -> `vaTk: TTypeKind` (the value it holds).
3. cparser.inc ~2923: added the missing `;` after `end` before the `if`.

Gates (all green): `fpc -O2 -Tlinux -Px86_64 compiler/compiler.pas` builds
clean; `make fpc-check` — the FPC-built compiler compiles compiler.pas to a
binary BYTE-IDENTICAL to the self-hosted `compiler/pascal26` (cmp clean); self-
host byte-identical; make test. `make bootstrap` (FPC cold-start) works again.

## Log
- 2026-07-08 — resolved, commit 197899d3.

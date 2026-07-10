---
prio: 58  # auto — 111 conformance tests behind it, biggest single unlock
---

# Parser requires `program` header — FPC allows headerless programs

- **Type:** bug (Pascal frontend, dialect fidelity)
- **Track:** P (shared `parser.inc` — A-gated, sole-A confirmation before edit)
- **Status:** backlog — filed 2026-07-10 from the FPC-testsuite audit
  ([[feature-pascal-corpus-fpc-testsuite]]).
- **Owner:** —

## Symptom
`Expected: program, but got: var/type/uses/const (Kind: N, Line: N)` — pxx
insists a program starts with a `program Name;` clause. FPC (and Turbo Pascal
back to 1.0) treat the header as optional: a source file that opens directly
with `uses`, `type`, `var`, `const`, or `begin` is a valid program.

Also in this cluster: `Expected: program, but got: unit` — several corpus
entries are units compiled standalone; FPC compiles a unit source to a `.ppu`
without a program. Decide: accept-and-compile-noop or clean "is a unit" error;
either beats "expected program".

## Impact
**111 of 294** curated-subset failures in the FPC conformance audit
(`tools/run_pascal_conformance.sh`) are exactly this — by far the biggest
single unlock. Skip-list reason: `parser: program header required`.

## Fix sketch
In the program parser: if the first token is not `program`, synthesize an
anonymous program name and fall through to the declaration section instead of
erroring. Watch self-host + `make test` (shared `parser.inc`).

## Gate
`make test` + self-host byte-identical; re-run
`tools/run_pascal_conformance.sh` and burn the 111 skip-list entries.

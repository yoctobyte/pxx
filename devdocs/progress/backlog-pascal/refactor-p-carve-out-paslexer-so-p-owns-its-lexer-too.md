---
track: P
prio: 55
type: refactor
blocked-by: []
summary: "The parser carve-out is done, but Pascal still shares lexer.inc with Track A — so the A/P no-concurrent-edit rule still binds, now over 2,566 lines instead of 37,249. Carve the Pascal-specific lexing into paslexer.inc the way C, NilPy, Rust and Zig already have their own, and the A/P slot stops existing."
status: backlog
owner: ""
---

# Carve out `paslexer` so Track P owns its lexer too

- **Track P** (Pascal frontend), file-owned jointly with A until it lands.
- Follow-up to [[refactor-a-carve-out-plexer-pparser-so-p-owns-its-own-files]],
  which finished the parser half on 2026-08-20: `parser.inc` went 37,249 lines
  → 109, into ten `pasparser_*.inc` files (P), four Track A files, and
  `pyforwards.inc` (N).

## Why it is still worth doing, and why it is not urgent

The A/P slot — "A and P must never edit these files concurrently", the rule the
coordinator exists to enforce — now keys on **`lexer.inc` (2,566 lines, 75
routines)** plus the Pascal-facing paths of `defs.inc` / `symtab.inc`, instead
of on a 37,249-line file both lanes had to queue behind. That is most of the
contention gone, which is why this is `prio: 45` and not higher.

What remains is the *principle*, and it is the one the repo keeps paying for:
every other frontend has its own lexer (`clexer`, `pylexer`, `rlexer`,
`zlexer`, `alexer`, `blexer`, `llexer`, `flexer`, `glexer`, `elexer`). Pascal
is the only one whose lexer is spelled with the generic name, and a generic
name is what let ~200 NilPy forwards and the AST arena accumulate inside the
Pascal *parser*. The same gradient applies here.

## Method — the one from the parser carve-out, which worked

**Cut CONTIGUOUS ranges and re-include each at the exact offset it occupied.**
A contiguous cut restored in place is identical by construction, so
`make compiler/pascal26` (the byte-identical fixedpoint) *proves* the move
rather than merely failing to object: across fourteen such cuts the emitted
code size did not change by one byte. Gate after **each** slice, never one big
move — include order is load-bearing in a single-pass compiler.

Two traps that actually fired last time, both worth reading before starting:

1. **Nested `{$include}` is available but only after a pin.**
   `make compiler/pascal26` compiles `compiler.pas` with the **pinned** binary.
   Recursive include expansion landed on 2026-08-20
   ([[bug-a-a-nested-include-is-silently-dropped]]) but a pinned compiler
   predating it drops the directive *silently*. Either list slices flat in
   `compiler.pas` (what the parser carve-out did) or confirm the pinned binary
   is new enough.
2. **The FPC seed is the canary, not the fixedpoint.** pxx pre-scans
   declarations; FPC does not. Moving a routine across an include boundary
   without moving its `forward` passes the fixedpoint and fails only the seed
   build. That happened, to exactly one line, and only `gate.sh quick`'s FPC
   canary caught it.

## Scope note — `pyparser.inc` is the same shape

`pyparser.inc` is **45,529 lines**, now the largest file in the compiler and a
monolith by the same mechanism. It does not serialize two lanes the way
`parser.inc` did (Track N owns it outright), so the concurrency argument does
not apply — but the second cost does: *"one concept, N independent sites"* bugs
are born in files too large to see the sibling path in, and that shape dominates
this repo's bug history. A separate Track N ticket, not this one.

## Gate

`make compiler/pascal26` fixedpoint after each slice + `tools/gate.sh quick`
(the FPC seed canary is the one that matters here).

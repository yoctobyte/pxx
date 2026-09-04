---
track: P
prio: 55
type: refactor
blocked-by: []
summary: "DONE in three slices. paslexer.inc exists and lexer.inc goes 3,758 -> 912 lines. Was: the parser carve-out was done, but Pascal still shared lexer.inc with Track A — so the A/P no-concurrent-edit rule still binds, now over 2,566 lines instead of 37,249. Carved the Pascal-specific lexing into paslexer.inc the way C, NilPy, Rust and Zig already have their own. The A/P slot SHRINKS rather than stops existing: lexer.inc still holds the shared diagnostics, token pool and token-stream cursor (Next/Eat/Expect drive every frontend), and defs.inc/symtab.inc are untouched. The body's 2,566-line count was stale by ~1,200 lines. Proof is NOT the binary sha -- a new file name enters the debug file table, so the compiler's own bytes must move (875d46034173 -> 01a25b518879, both from the pin seed) -- but a byte-comparison of the code it EMITS over 88 directive- and literal-heavy sources: 78 identical, 0 differing, against a control reporting 68 of 68 differing versus the pinned compiler."
status: done
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

---

## 2026-09-05 (frankA) — DONE in three slices, and the method needed one correction

`compiler/paslexer.inc` exists. `lexer.inc` goes **3,758 → 912 lines**.

**The body's "2,566 lines, 75 routines" was stale by ~1,200 lines and 24
routines** — measured 3,758 / 99 at `6cab0dfdb`. That number is the ticket's
whole case for "most of the contention is already gone", so it was understating
the remaining A/P surface by a third. Recounted, not remembered.

| slice | moved |
| --- | --- |
| 1 (`bed07c3d6`) | the directive and conditional machinery, `SkipSpace`, `PasAtLineMarker`, `PasLexLineMarker`, `LexOne`, `LexAll` |
| 2 | `Keyword` |
| 3 | `AddPasUnitDir`, `AddPasIncDir` |

Stayed, because more than one frontend calls them: the diagnostics block, the
token pool, `AppendChar`/`AppendString`/`AppendRange`, `GetTokenStrFromRaw`,
`WriteTokenContext`, `StrToDoubleBits`, `DecDigitsExceed`, and the token-stream
cursor — `LexAppend`, `InsertTokens`, `RemoveTokens`, `Next`, `Eat`, `Expect`.
Every frontend's parser drives those last three.

**One forward declaration is the entire cost**: `LexAppend` is shared and calls
`LexOne`, which moved.

### The correction: "byte-identical by construction" is false for the compiler's OWN binary

The method section says a contiguous cut restored in place *"is identical by
construction, so `make compiler/pascal26` PROVES the move"*, citing fourteen
cuts where **the emitted code size** did not change by one byte. Those are two
different claims and this carve-out separates them: a new source file name
enters the debug file table and every carved line changes number, so the
compiler's own bytes MUST move. Measured, both seeded from pin v403 and both
converging: **875d46034173 pre-cut → 01a25b518879 post-cut.**

Read as the ticket words it, that difference is an alarm. It is not one. The
claim worth gating on is about the code the compiler EMITS, so that is what was
measured instead:

- **88 sources selected for `{$ifdef}`, `{$mode}`, `{$include}`, conditional
  expressions and numeric literals** — chosen so the corpus reaches the moved
  machinery, rather than a general corpus that would pass by not touching it.
- Compiled by the pre-carve and post-carve compilers and byte-compared:
  **78 identical, 0 differing, 10 refused by both** (six negative tests, two
  units, two needing lib paths).
- **Positive control on the same harness against the pinned compiler: 0
  identical, 68 differing.** It can say no.

Whoever does `pyparser.inc` should measure it this way and not by the sha.

### The cut is not "everything between these two routines"

`DecDigitsExceed` sits in the middle of the conditional-expression machinery, is
named for nothing Pascal, and is called from `pylexer.inc`, `ir.inc` and
`pasparser_expr.inc`. It stayed, splitting the moved region in two.

**One of those three callers is two hours younger than the census that found the
other two** — frankB landed it mid-window and said so. A routine with no
external callers in the morning had three by that night, so *"nothing outside
this file calls it"* is a claim with a timestamp on it. Judge these by callers,
re-derived at the moment of the cut, not by neighbours.

### Four doc citations were already stale and are now repointed

`lexer.inc:936`, `:1012-1023`, `:1844` and `:628` in `wasm-target-findings.md`,
`wasm/PLAN.md`, `threading.md` and
[[compat-pascal-the-strict-fpc-flag-family-is-incomplete]] all resolved to blank
lines or unrelated fragments **in the pre-carve file** — stale before this work,
not by it. Repointed at file + routine rather than a line, which is the
precedent CLAUDE.md set when three `Makefile:<n>` citations drifted 142 lines.
History files (`session-roster-history.md`, `BOARD-done.md`) deliberately left
alone.

### What this does NOT close

The A/P slot shrinks but does not vanish: `lexer.inc` still holds the shared
diagnostics, token pool and cursor, and the Pascal-facing paths of `defs.inc` /
`symtab.inc` are untouched. The token/node-numbering coordination rule is
unaffected — this moved bodies, it renumbered no `tkXxx` or `AN_Xxx`.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 1cfd034f1.

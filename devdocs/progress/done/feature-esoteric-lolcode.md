---
prio: 45  # auto
---

# Esoteric probe: LOLCODE

- **Type:** feature — esoteric-frontend-probe
- **Status:** done (2026-07-06) — skeleton landed, probe closed
- **Umbrella:** [[feature-esoteric-frontend-probes]]
- **Opened:** 2026-07-05

## What it is

Lolspeak-themed esolang: `HAI`/`KTHXBYE` (program bounds), `I HAS A` (declare),
`VISIBLE` (print), `GIMMEH` (read), `O RLY?`/`YA RLY` (if), `IM IN YR`/`IM
OUTTA YR` (loop), `SMOOSH` (string concat). Dynamically typed with loose
implicit casting between string/int/float/bool.

## Why it's a good probe

Dynamically typed + loosely cast — different type-checking path than anything
static-typed PXX parses today. Closest existing comparison is Nil Python's
dynamic surface; this hits it from a different, sillier angle. Likely the
cheapest candidate in the umbrella — no generics, no ownership, no exotic
control flow beyond what BASIC already has.

## Scope (skeleton only — see umbrella for the category rule)

Lexer + parser for the subset above, lowering onto existing IR (probably via
the same boxed/tagged-value approach Nil Python's dynamic typing already uses).
Stop once a trivial `HAI ... VISIBLE "HAI WORLD" ... KTHXBYE` program compiles
and runs, or a shared-internals bug surfaces trying to get there.

## Acceptance

Either: (a) a shared IR/codegen/ABI bug is found and filed as its own Track A
ticket, or (b) the trivial subset compiles and runs clean — both are a
successful, closed probe. Do not extend past the trivial subset either way.

## Log
- 2026-07-05 — filed as part of the esoteric-frontend-probes umbrella.

## Probe done (2026-07-06, Track Z session)

Skeleton landed, additive-only per the Ada/Zig pattern: `compiler/llexer.inc`
+ `compiler/lparser.inc` (new), `isLol` + `.lol` dispatch in compiler.pas,
one-line var in defs.inc. lparser reuses rparser.inc's node helpers.

**Landed subset:** HAI/KTHXBYE, `I HAS A x [ITZ expr]` (type inferred:
NUMBR->Int64/YARN->string/TROOF->bool), `x R expr`, VISIBLE with multiple
operands, prefix ops SUM/DIFF/PRODUKT/QUOSHUNT/MOD OF, BOTH SAEM/DIFFRINT,
`<expr>, O RLY? YA RLY/NO WAI/OIC` (the expression IS the condition — the
IT variable is explicitly out of scope, a bare expression statement errors
loudly instead of silently vanishing), IM IN YR/IM OUTTA YR + GTFO, SMOOSH
... MKAY string concat (tkPlus chain), WIN/FAIL, BTW/OBTW..TLDR comments,
newline/comma statement separators. Test: test/test_lolcode_skeleton.lol in
make test.

**Probe verdict: no shared-internals bug.** Dynamic-typing angle reduced to
declare-time inference (honest skeleton cut). One frontend-local bug during
bring-up, and it was the documented paramless-recursion pitfall AGAIN
(`a := LParseExpr;` inside LParseExpr's own body reads Result instead of
recursing — third frontend in a row to hit a variant of this; the pitfall
memory earns its keep).

Acceptance (b) met: trivial-plus subset compiles and runs clean. Closed at
skeleton depth per the umbrella cap.

---
prio: 45  # auto
---

# Esoteric probe: Whitespace

- **Type:** feature — esoteric-frontend-probe
- **Status:** done (2026-07-06) — skeleton landed, prescan bug filed, probe closed
- **Umbrella:** [[feature-esoteric-frontend-probes]]
- **Opened:** 2026-07-05

## What it is

Esolang whose only meaningful characters are space, tab, and linefeed — every
other character is a comment. A stack-machine instruction set (push/dup/swap,
arithmetic, heap access, labeled jumps, I/O), directly bytecode-shaped rather
than expression-shaped.

## Why it's a good probe

The opposite extreme from every other frontend's lexer: no visible tokens at
all, and the source language is already a flat stack-machine, not an
AST-shaped language — lowering it onto PXX's AST/IR means going
bytecode-instructions → AST nodes, backwards from how every other frontend
works (source syntax → AST → IR). Different lexer shape AND a different
lowering direction; good diversity for the fuzz-probe goal.

## Scope (skeleton only — see umbrella for the category rule)

Lexer that recognizes only whitespace runs as instruction encodings; a
minimal instruction set (push, print, exit) proving the pipe end-to-end.
Stop there — a full Whitespace VM (heap ops, labeled jumps) is not the point.

## Acceptance

Either: (a) a shared IR/codegen/ABI bug is found and filed as its own Track A
ticket, or (b) the trivial subset compiles and runs clean — both close this
probe successfully. Do not extend past the minimal instruction set.

## Log
- 2026-07-05 — filed as part of the esoteric-frontend-probes umbrella.

## Probe done (2026-07-06, Track Z session)

Skeleton landed: `compiler/wparser.inc` (new; NO lexer file — the frontend
never touches Tokens[]/CurTok and reads Source[] char-by-char, since S/T/L
are the only meaningful characters), `isWs` + `.ws` dispatch in compiler.pas,
state vars in defs.inc. The stack-machine → AST direction worked as designed:
a compile-time stack of AST node ids folds push/dup/discard and
add/sub/mul/div/mod into expression trees; only the two output instructions
emit statements (AN_WRITE). Labels/jumps/heap/read stay out per the cap.
Test: test/test_ws_skeleton.ws (prints Hi\n40\n2\n36) in make test.

**Probe verdict: one real shared-internals find** — an include-level `var`
section at wparser.inc's (late) include position trips the impl prescan's
"global declared later" error even though the declarations lexically precede
every use; the identical shape works at bparser.inc's earlier position.
Filed as [[bug-impl-prescan-late-include-var-section]] (Track A) with a
repro sketch; worked around by declaring the state in defs.inc. Also
re-confirmed a known limitation loudly (nested routines can't capture
fixed-size arrays — existing explicit compiler error, no ticket needed).

Acceptance (a) met: shared-internals bug found and filed. Closed at skeleton
depth.

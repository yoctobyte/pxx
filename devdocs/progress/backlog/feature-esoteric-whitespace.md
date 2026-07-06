---
prio: 45  # auto
---

# Esoteric probe: Whitespace

- **Type:** feature — esoteric-frontend-probe
- **Status:** backlog
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

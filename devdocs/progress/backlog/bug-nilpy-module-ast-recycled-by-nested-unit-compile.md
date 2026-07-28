---
track: N
prio: 85
type: bug
---

# A .py module's statement list is RECYCLED while it is still being built

`from convertrawtext import FormatText` — importing a real `.py` module —
fails with

```
pascal26:1961: error: invalid IR symbol reference in load_sym
```

at the module's LAST line, with nothing there to explain it. This is the wall
between songformatter's own modules COMPILING (they do, standalone) and
`SongFormatter.py` compiling at all: it imports `convertrawtext`, which imports
`render_backend`.

## Cause, measured

The AST arena is **per-proc scratch**. Every Pascal body compile ends with
`ASTNodeCount := INLINE_AST_RESERVE` (8192) — nine sites in `parser.inc`, two
in `cparser.inc` — so the nodes above the reserve are handed out again for the
next body. That is sound while one parse is live.

A NilPy module violates it: `ParsePyUnit` accumulates the module's import-time
statements into a chain that stays live across the WHOLE file, and parsing that
file compiles other units — `tkinter`, a sibling `.py` — whose bodies reset the
arena underneath it. Instrumented, with four modules in flight:

```
DBGUNIT settings       seqNode=8192  kind=19(AN_SEQ)   astcount=10617
DBGUNIT key_analysis   seqNode=10773 kind=19(AN_SEQ)   astcount=23461
DBGUNIT render_backend seqNode=8192  kind=24           astcount=11076   <- reused
DBGUNIT _cut           seqNode=11076 kind=3(AN_IDENT)  astcount=28472   <- reused
```

Both of the later modules' statement lists had been re-allocated as something
else. `_cut`'s import-time proc then compiled a lone `AN_IDENT` — one
`load_sym` of an anonymous variant temp whose symbol had been rolled back with
the scope that made it, which is the error above.

The same cause explains `render_backend.py` failing standalone with `invalid
symbol in lea`.

## What was tried, and why it is not landed

An **arena FLOOR** (`ASTArenaFloor`, raised to `ASTNodeCount` while a NilPy
module parse is live, and every reset site clamped to it) fixes the recycling
exactly as intended — and immediately exposes a SECOND defect underneath, which
the corruption had been masking: with the nodes preserved, the program body's
hoist chain reaches lowering with a stale entry (`IR_UNSUPPORTED` kind 9 =
AN_ARG, or an `IR_LEA` of a rolled-back symbol), and `convertrawtext.py`, which
compiled as a program before, then does not. Reverted rather than shipped: it
trades a broken import path for a broken program path.

The floor is still believed to be the right shape. The second defect has to be
found first. Evidence gathered on it:

- The bad IR lands in the **program body** (`CurProc = -1`), whose own statement
  list is only two assignments — everything else in it arrived through
  `mainNode := PyFlushHoist(mainNode)`.
- The last thing queued before the failure is the SAME node id queued three
  times (`DBGQ line=413 proc=966 node=11054 kind=12`), which is what a
  multi-iteration typing pre-pass produces once `ASTNodeCount` has been rolled
  back to the same watermark each round. Appending a node already in the chain
  makes the chain self-referential — a plausible source of the 153-instruction
  body a two-statement module compiled to.
- `PyCollectLocalsAST` and `PyCollectModuleLocalsAST` already discard the queue
  after a trial parse; `PyParseDef` now discards its body's residue, and
  `PyParseFallbackImportTry` discards what a SKIPPED block queued. None of those
  is the remaining leak.

## Which modules it bites

Measured on songformatter, importing each module on its own:

| module | imports another `.py`? | result |
| --- | --- | --- |
| `settings.py` | no | imports clean |
| `key_analysis.py` | no | imports clean |
| `render_backend.py` | no | imports clean |
| `convertrawtext.py` | yes (settings, key_analysis, render_backend) | **fails** |

So one level of `.py` import works — the module loader is fine. It is the
NESTED parse that recycles: the outer module's statement list is live while the
inner module's own unit imports reset the arena.

## Suggested shape

Either give `PyHoistStmt` a cycle guard (refuse a node already on the chain,
which is never legitimate) and re-land the floor, or stop the module from
holding AST across unit compiles at all — record its statements' TOKEN spans and
re-parse them into the init proc, the way a Pascal `initialization` section is
parsed and compiled in one pass.

## Gate

`make test-nilpy`, plus a two-module `.npy` pair where the imported module has
module-level statements AND imports a Pascal unit of its own — that is the
minimum shape that recycles.

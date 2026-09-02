---
slug: feature-a-prune-statements-after-a-return-at-O0
track: A
prio: 55
type: feature
status: done
blocked-by: []
found: 2026-09-02
found-by: frankC
owner: frankC
summary: "DONE (916fc9cd4). Statements behind an unconditional transfer -- Exit/Halt/Break/Continue/raise/goto/goto* -- are no longer emitted, at -O0 and every level, in BOTH frontends; -OO still emits them via the SourceOneToOne gate at the helper. The third shape of the consensus dead-code core, and a DIFFERENT MECHANISM from the if/while prune: statement-sequence reachability, not a constant condition. The decision lives in ONE function, ASTSeqTailUnreachable in ast_arena.inc, because ir.inc has TWO chain walks -- the AN_SEQ spine and the AN_BLOCK cons walk a C function body takes -- and a prune that lived only in the spine pruned nothing for C. Label-escape guard unchanged and measured both ways: patched out, both repros are REJECTED at build time rather than miscompiling. Acceptance met by an isolating pre/post differential over all 2201 corpus files: 0 image differences at -O2, 45 files changed at -O0 and all 45 identical at -O2, 0 build asymmetry."
---

# Prune statements after a return at -O0

Split from [[feature-a-fold-the-consensus-dead-branch-core-at-every-level]],
whose parts 1 (`if`/`while`), 2 (escape guard), 3 (`-OO`) and 4 (charter) are
done. This is what its part 1 listed third and nothing has closed.

## Measured, 2026-09-02, at the tree that landed the `if`/`while` prune

```pascal
procedure P; begin Exit; WriteLn(NeverR); end;   { never_r_P declared, undefined }

-O0   rc=127  undefined symbol: never_r_P
-O2   alive
-O3   alive
```

`IROptDeadCode` catches it from `-O1` up. `-O0` is the only failing level.

## Why it was NOT bolted onto the prune that landed

`if False` and `while False` are one question — **is this condition a
constant** — answered by one helper (`ASTConstCond`) at two sites. This is a
different question: **which statements in a sequence are still reachable**,
which needs a notion of which node kinds TERMINATE a block (`Exit`, `return`,
`goto`, `Halt`, a raise, a call to a `noreturn`), applied while walking
`AN_SEQ`. Bolting it onto a constant-condition fold would have been the second
path that stays broken (`normalise-dont-special-case`).

## Constraints inherited from the parent, both non-negotiable

- **The label-escape guard applies unchanged.** A statement after a return that
  carries `AN_LABEL` / `AN_LABELADDR` / `AN_GOTO_INDIRECT` is reachable by
  `goto` and must be KEPT — this is how `goto`-based cleanup epilogues are
  written, so it is the common case in C, not a corner.
- **`-OO` must keep emitting it.** The gate is `SourceOneToOne`, checked at the
  helper rather than the call site, so a new fold inherits it automatically.

## Acceptance

- The shape above links and runs at every level, `-O0` included.
- A label after a return still resolves at every level.
- `-OO` still emits it (assert the FAILURE, as `test_source_one_to_one_oo.pas`
  does — a flag that silently did nothing would pass a success assertion).
- Isolating pre/post differential over the corpus: image identity at `-O2`
  (the existing pass already reached this fixed point, so the new lowering must
  agree with it, not compete), output identity at `-O0`.

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

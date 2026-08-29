---
slug: feature-a-wasm32-compile-check-the-phase-2-backend
title: "Include ir_codegen_wasm32.inc and forward IRTopLevelStmt in compiler.pas — the staged half of the Phase 2 wiring"
track: A
prio: 55
type: feature
blocked-by: []
status: done
owner: frankwasm
created: 2026-08-28
summary: "Two lines in compiler.pas: {$include ir_codegen_wasm32.inc} beside the other backends, and a forward for IRTopLevelStmt. Granted separately from the module-writer wiring, with the dispatch arm explicitly withheld. Behaviour change zero. Filed late — the grant existed only in a branch commit message, which is filing it nowhere."
---

# Why this is being filed after the fact

`feature-a-wasm32-module-writer-wiring` granted three `compiler.pas` edits and
closed with **"Anything beyond those two is a new conversation."** That
conversation happened and the grant was given, but it produced only a commit
message on the `wasm` branch (`05ec4ac00`) and no ticket. So `compiler.pas`
carried five distinct edits on the branch while master's record accounted for
three.

The coordinator caught it by diffing the branch rather than reading the merge
summary, which is what the standing "nothing is pre-approved" ruling exists for.
The lane's own reply had listed four shared-file arms and omitted `compiler.pas`
entirely — the summary was wrong, and only the diff said so.

This is the same defect `test/wasm/check_tickets.sh` was written for, one level
up. That check makes an unfiled *ticket* unrepresentable. It cannot see an
unfiled *grant*: a shared-file edit whose only record is a branch commit is
invisible to master, to the ranker, and to whoever reviews the merge — and it
reads as covered, because a neighbouring ticket covers the file.

**A grant recorded only in the commit that used it is not a record.** The commit
is the thing being justified; it cannot also be the justification's index.

# The edits, verbatim from the branch

1. `{$include ir_codegen_wasm32.inc}` beside the other backends.
2. `function IRTopLevelStmt(k: Integer): Boolean; forward;` in the shared
   forward block.

The dispatch arm was **explicitly withheld** and was a separate ask. Behaviour
change from these two: exactly zero — nothing called `IREmitMachineCodeWasm32`,
and `--target=wasm32` still errored in the `ir_codegen.inc` dispatch, unchanged.

# Why the forward rather than a reordering

`compiler.pas` already forwards `IRNodeOwnsManagedStr` for precisely this
structural reason — the cross backends are included **before** `ir_codegen.inc`
— and says so in a comment beside it. So this uses the mechanism the file
already has for this situation instead of adding a second one
(`normalise-dont-special-case`). The argument that carries is "same mechanism,
same reason", not "it is small". Note the forward block is also the region that
produced this lane's two FPC-seed REDs, so it is not a free place to add a line.

# What the include bought, and how it was checked

228 lines written blind became COMPILED. Unlike `wasmenc.inc`, this file depends
on `Syms`, `Procs`, `IRKind`, `CurProc` and `FrameSize`, so no standalone
harness for it means anything.

It compiled on the first attempt, which was treated as suspicious rather than
accepted, and verified three ways: two distinctive strings from the file were
present in the binary; a deliberately broken procedure appended to it was caught
(`pascal26:232: error: undefined variable (this)`); and removing that restored
the same fixedpoint. The file is genuinely compiled, not silently skipped.

# Gate — as run at the time

- `make compiler/pascal26` → `converged after 1 round(s)`, `8dedbc7a0e07`
  (was `a5ba15590962`).
- No existing target moved: 4 programs x 6 targets = 20 output hashes identical,
  **both sides regenerated back-to-back** rather than reusing an earlier
  baseline — Track O had found that a pin landing `lib/rtl` between two hash
  runs made six targets look changed.
- `check_phase1.sh` and `proto/check.sh` green under the new binary.

# Consequence for the merge

`compiler/compiler.pas` is a shared-file arm of the `wasm` branch and belongs in
the merge accounting alongside `exception_emit.inc` (x2) and `ir_codegen.inc`
(x1). Five edits total in the file, three covered by
`feature-a-wasm32-module-writer-wiring` and two by this ticket. **"Covered by a
prior ticket" and "not a shared-file change" are different claims**, and only the
first is true of any of them.

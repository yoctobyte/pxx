# Handoff: fix `bug-managed-length-via-pointer-deref` (Track A)

You are Track A (compiler, `compiler/**`). Fix managed `Length(ps^)` /
`Length(rec.pf^)` returning garbage on every target.

Ticket: `docs/progress/backlog/bug-managed-length-via-pointer-deref.md` (read it).
Move to `working/` while active, `done/` when finished; regen BOARD.md.

## The bug, exactly

```pascal
type PStr = ^string; var s: string; ps: PStr;
begin s := 'TRoot'; ps := @s; writeln(Length(s)); writeln(Length(ps^)); end.
{ should be 5 5; managed default gives 5 <garbage> (x86-64 5 500085772884,
  i386 5 1869566548). Direct Length(s) is correct; only the deref is wrong. }
```

Only under managed strings (the default). Same for `Length(rec.pf^)` where
`pf: ^string`.

## Why (root cause, confirmed)

`@s` of a managed string = address of the handle slot. So `ps` holds `&slot`,
and `ps^` in address context lowers (ir.inc:817 `AN_DEREF` →
`IRLowerAST(ASTLeft)`) to just *load ps* → `rax = &slot` (the pointer value).

`Length`'s arg-lowering force-addresses any lvalue (ir.inc:3030,
`isRefArg := IsASTLValue(ASTLeft[item])`), so the arg comes in as that
`&slot`-valued node, tagged `tyAnsiString`.

The x86-64 Length codegen (ir_codegen.inc:3210-3263) enters the managed branch
(3214) but `ps^` matches **none** of the extra-deref sub-cases there:
- 3218 by-ref managed param,
- 3223 `IR_FIELD`/`IR_INDEX` (managed field/element),
- 3245 `IR_INDEX`/`IR_FIELD` + `tyPointer` (dyn-array handle in a slot).

So it falls to 3227: `test rax` then `mov rax,[rax-8]` on `rax = &slot` →
reads the word *above the slot*, garbage. It needs **one extra deref**: from
`&slot` → `mov rax,[rax]` (= the data/handle ptr) → `[rax-8]` (length). Exactly
the IR_FIELD/IR_INDEX treatment at 3223. The deref case is simply missing.

## Already attempted + reverted (do NOT repeat)

Routing the managed deref to the VALUE path (so it lowers to a tyAnsiString
handle and the 3214 branch reads `[-8]` directly) made the read correct (5) but
then **segfaulted**: the borrowed `ps^` handle got treated as a materialised
managed temp and released → double-free of `s`. So **stay on the
address/ref path** and fix the deref LEVEL; do not go value-path.

Good news: the managed-temp owning path already EXCLUDES `AN_DEREF`
(ir.inc:3088, `argIsManagedTemp` requires kind <> AN_DEREF), so ownership is
already correct on the ref path. The ONLY defect is the missing deref in
codegen.

## Fix plan (pick the cleaner of two; lowering is likely tidier)

The hard part is letting codegen *recognise* "this Length arg is a
pointer-deref of a managed string" — after lowering, `ps^` is an indistinct
load. Two candidate sites:

1. **Lowering (ir.inc, near the dyn-array-call special-case at 3056).** Add a
   sibling case: `(-cpi = Ord(tkLength)) and pathIdx = 0 and
   ASTKind[ASTLeft[item]] = AN_DEREF` and the pointed-at type is a managed
   string. Lower it to a node the existing "&handle → load → [-8]" path
   (codegen 3245) already consumes — i.e. produce the `&slot` value tagged
   `tyPointer` with an IR kind that branch keys on. May need a small dedicated
   IR shape (an `IR_DEREF`/`IR_LEA` carrying "address of a managed handle").
2. **Codegen (all 6 backends).** Make the managed Length branch detect the
   deref node kind and emit the extra `mov rax,[rax]` before `test`/`[-8]`,
   mirroring the 3223 IR_FIELD/IR_INDEX case. Requires the deref to survive
   lowering as its own IR kind (it currently collapses to a plain load), so
   this probably still needs a lowering tweak to keep the deref visible.

Whichever: the per-target Length codegen lives in **all six** backends —
`ir_codegen.inc` (x86-64), `ir_codegen386.inc`, `ir_codegen_aarch64.inc`,
`ir_codegen_arm32.inc`, `ir_codegen_riscv32.inc`, `ir_codegen_xtensa.inc`. Grep
each for the managed `Length` / `[-8]` (`rax-8` x86; equivalents elsewhere) and
add the same extra-deref level. 32-bit targets read a 4-byte word; mind word
size (the garbage differs per word size — that's the symptom, not a second bug).

## Verify

- Repro above → `5\n5` on x86-64 AND i386 (and a quick aarch64/arm32 run).
- `Length(rec.pf^)` variant (record field of type `^string`) → correct.
- Re-add a MANAGED variant test: `test_cross_frozen_strlen_deref` was repointed
  to `-uPXX_MANAGED_STRING` (frozen, already correct) to dodge this. Add a
  managed-default test (`test/test_managed_strlen_deref.pas`) + Makefile line,
  asserting both reads equal.
- No double-free: run under the repro twice / in a loop; clean exit.

## Gate

This is **IR/codegen** (touches `ir_codegen*.inc` and/or IR lowering), so per
[[feedback_gate_by_change_type]] run the **full `make test`** (+ cross:
`make test-i386 test-aarch64 test-arm32` and `make cross-bootstrap`), not just a
self-host. The gate is FPC-free now (see `docs/dev/fpc-optional-workflow.md`);
`make test` self-hosts off the existing binary. If you change codegen the
self-host may reseed one generation (`feedback_codegen_reseed_not_nondeterminism`)
— re-run, expect g2==g3. Pin only if Track B needs it.

## Landmines

- Managed paths are NOT exercised by the compiler's own self-build (it builds
  frozen, byte-identical) — a managed-only codegen bug passes self-host
  silently. You MUST run the managed repro by hand on each target.
- Don't reach for `make bootstrap` (FPC) out of habit — `make test` is the
  FPC-free gate now.
- `git pull --rebase` before push (3 parallel agents). Exclude `.claude/` and
  `compiler/pascal26*` build artifacts from commits.

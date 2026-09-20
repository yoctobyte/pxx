---
slug: feature-a-dce-can-drop-a-body-whose-only-stub-target-is-a-thunk-that-body-owns
track: A
prio: 40
type: feature
status: new
created: 2026-09-20
found-by: frankS
blocked-by: []
summary: "DceRangeHoldsStub roots any body whose address range contains a CodeRef target, which is correct for a target something EXTERNAL jumps into and over-approximate for the commonest case: a managed-local sweep thunk, which is called only by the body it sits in. Measured 2026-09-20 on examples/esp32/nilpy-c3 (riscv32, --platform=esp --dce): 128 bodies and 819,480 B -- 39.6% of live code -- are rooted `holds a stub target`, and every one of those targets is a sweep thunk placed by EmitProcScopeExitCleanupForTarget after the body's second return. The pass already has what it needs to tell the two apart: DceOwnerOf(target) names the body the target is inside, and EmitSweepThunkCall's call site is inside that same body, so an OWNED target could be treated as an ordinary intra-body reference and the body dropped when its owner is dead. That would make riscv32's live set match windowed xtensa's WITHOUT disabling the thunk -- xtensa is only smaller because TargetHasSweepThunk excludes the windowed ABI, which is a trade, where this is not. The root rule must STAY for genuinely unowned targets; the change is to stop applying it where the owner is also the only caller."
---

# DCE can drop a body whose only stub target is a thunk that body owns

Split out of [[bug-a-riscv32-dce-keeps-135-more-bodies-than-xtensa-on-one-program]],
which is answered. That ticket asked whether xtensa's smaller live set was a
win or a pass running blind; the answer is neither — it is an ABI consequence.
**This is the opening the answer exposed**, and it is filed separately because
a residual in the tail of a closed question does not get read.

## The mechanism

`EmitProcScopeExitCleanupForTarget` inlines a managed-local sweep on a body's
first return. On the **second** return, with at least `SWEEP_THUNK_MIN_SLOTS`
(3) releasable slots, it places an out-of-line thunk *after* that return and
calls it — so the thunk's address is 1–5 KB into the body, not at its entry.
`EmitSweepThunkCall` routes that call through `EmitRiscv32CallToCode` /
`EmitXtensaCallToCode`, both of which record a CodeRef.

`DceRangeHoldsStub` then sees a CodeRef target inside that body's range and
roots the body. That rule is right in general — a body something jumps into
cannot be dropped — and **wrong for this case specifically**, because the only
thing that jumps into it is the body itself.

## The measurement it is worth

`examples/esp32/nilpy-c3/main/main.npy`, riscv32, `--platform=esp --no-signals
--dce`, compiler at `734c1df1e`:

```
stub targets 143, of which 139 land inside a body
819,480 B across 128 bodies rooted `holds a stub target`   (39.6% of live code)
```

Named, with the offset inside the body: `BAddSigned +1280`, `BDivMod +4788`,
`BShr +2896`, `PXXPromoFromStr +3544`, `SubSlowVV +2976`, `PXXPromoMod +2496`.
Those offsets are the tell — a target 4,788 bytes into a body is not an entry
a table happens to name.

**819,480 B is the CEILING, not the estimate**, and the distinction matters.
It is the total rooted by this rule; how much of it is reachable some other way
is unknown, because the report attributes by FIRST reason and this rule fires
before the reachability walk. A body rooted here may well also be called. **The
honest version of the win is "somewhere between 0 and 819,480 B", and finding
out is part of the work** — the same first-reason blindness the umbrella's own
bullet warns about.

## Why this is a win and not a trade

Windowed xtensa has zero in-body stub targets because `TargetHasSweepThunk`
excludes it — sp is constant and a0 is the live return address, so a thunk has
nowhere to put either, and the sweep is inlined at every return instead. That
is smaller code for this reason and larger code at every other return site.

This change needs no such trade: the thunk keeps its size win and the pass
stops treating a self-call as an external entry point.

## The guard this needs

**A positive control drawn from the right population: a body whose stub target
is genuinely UNOWNED must still be rooted.** The entry stub's target is one
(`ir_codegen.inc` patches the program entry jump at a target with no `Procs[]`
row, so `DceOwnerOf` returns −1). Assert both arms — a version that drops
everything passes a test that only checks the new behaviour.

`test/test_dce_sweep_thunk_abi.pas` already pins the ABI asymmetry and should
grow a row here: after the change, riscv32's in-body target must stop rooting
`F` when nothing calls `F`.

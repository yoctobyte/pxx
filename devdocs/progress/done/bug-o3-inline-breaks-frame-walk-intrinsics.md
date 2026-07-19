---
track: A
prio: 60
type: bug
---

# -O3 inlining deletes a frame the stack-frame intrinsics can observe

Track T NEW-RED (`optdiff#shard0/6`, sha 69f7bda93ac4, and the older
shard4/shard5 opens): `test/test_stack_frame_intrinsics_b270.pas` differed
between -O0 and -O3 with rc 0 both sides — a silent miscompile.

```
< per-site distinct: TRUE      (-O0/-O2)
> per-site distinct: FALSE     (-O3)
```

## Root cause

`function Where: Pointer; begin Result := CallerAddr; end;` is shape 1 for
retained-inline-body (`TryRetainInlineBody`, parser.inc), and the non-leaf
slice accepts the `CallerAddr` call in the RHS. At -O3 the inline gate
(`ir.inc`, `InliningActive < 2`) splices it, so `Where`'s physical frame
disappears and `CallerAddr`'s two `get_caller_stackinfo` steps land one frame
too high — on the return address into `Probe`'s caller, which is the SAME for
all three call sites instead of each site's own.

`get_frame` / `get_pc_addr` / `get_caller_stackinfo` read the LIVE saved-fp
chain, so the number of PHYSICAL frames between a walker and its target is
observable program state. Inlining is not semantics-preserving in its
presence — this is a general class, not one test's quirk.

## Fix

`FrameIntrinsicUsed` (unit-wide, set at parse of any of the three intrinsics)
plus `ProcFrameSensitive[]` (this proc uses one directly). The IR inline gate
declines when `FrameIntrinsicUsed and (ProcFrameSensitive[cpi] or
InlineBodyHasCall[cpi])`. Read at IR time, so it is order-independent —
by then the whole unit is parsed. Leaf retained bodies still inline: they add
no frame that a walk could pass through. Zero cost for any unit that never
names an intrinsic (the overwhelming majority), so -O2/-O3 are otherwise
untouched.

## Gate

`--tier quick` GREEN · self-host fixedpoint byte-identical ·
`optdiff#shard0/6`, `#shard4/6`, `#shard5/6` all GREEN (were the open
regressions).

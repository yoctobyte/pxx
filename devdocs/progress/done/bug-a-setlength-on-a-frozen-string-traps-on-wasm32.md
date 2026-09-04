---
track: A
prio: 25
type: bug
blocked-by: []
summary: "SetLength on a frozen string traps on wasm32 with `wasm trap: unreachable`. WasmEmitSetLenStr has no frozen arm at all: it unconditionally calls the MANAGED string runtime routine PXXStrSetLen with the slot address, so a frozen slot is handed to code that expects a heap handle. Confirmed under the pinned compiler, so it predates the byte-prefix conversion, and it is a missing feature failing loud rather than a prefix-width bug — it traps at default as well as under -dPXX_SHORTSTRING."
status: done
owner: ""
---

# `SetLength` on a frozen string traps on wasm32

Found 2026-09-02 — first hit by frankc-af while probing candidates for a
`test-wasm32` target, and it is the cause of three of the five red rows in that
sweep (`test_cross_sets`, `test_frozen_string_cross_b305`,
`test_static_string_literal`, all dying at rc 134). Diagnosed here.

## Repro

```pascal
var s: string[10];
begin
  s := 'abcde';
  SetLength(s, 1);
  WriteLn('[', s, ']');
end.
```

wasm32: `wasm trap: unreachable`, rc 134. Native: fine.

## The cause, and it is not the length prefix

`WasmEmitSetLenStr` in `compiler/ir_codegen_wasm32.inc` is four lines of body
and has **no frozen arm**:

```pascal
WasmEmitValueAs(IRA[node], WT_I32, 'slot address of SetLength');
WasmEmitValueAs(IRB[node], WT_I32, 'SetLength count');
if not WasmCallRtl('PXXStrSetLen') then Exit;
```

`PXXStrSetLen` is the MANAGED string routine — it expects a slot holding a heap
handle whose header sits below it. A frozen slot holds `[len][chars]` inline, so
it is handed a buffer where a handle is required.

For a frozen string the operation is not a runtime call at all: it is a clamp to
the capacity and a store of the new length into the prefix — the same prefix the
conversion now writes through `WasmFrozenStoreLen`, so the machinery to do it
correctly at either width already exists in the file.

## Pre-existing, with the control

Traps identically under `stable_linux_amd64/default/pinned`
(`1eec4dc5e0a74c69`), and traps at **default** as well as under
`-dPXX_SHORTSTRING`. So it is neither caused by nor related to the byte-prefix
work: it is a lowering that was never written.

## Why p25

It fails LOUD — a trap with no wrong value produced — and the frozen `SetLength`
shape is not on any current milestone. The three sweep rows it blocks are real
but are excluded from the wired `test-wasm32` set with a comment, so their
absence is recorded rather than silent.

## FIXED before 2026-09-04, and NOT by the change that noticed it

Re-measured 2026-09-04 while closing the two frozen-deref tickets in this
family. This ticket's repro verbatim, on wasm32, at default AND under
`-dPXX_SHORTSTRING`: `[a]`, rc 0. Three more rows, wasm32 against native, all
identical: shrink `[a] 1`, grow to 5, clamp at the capacity 10, and cap 256
(the wide prefix) `[ab] 2`.

**Not this session's change.** The same four rows are green on a compiler built
from the parent commit as well, so nothing here is claimed for the deref fix —
the control was run precisely to avoid claiming it.

**The residual question, answered rather than left open.** `WasmEmitSetLenStr`
STILL has no frozen arm and still calls `PXXStrSetLen` unconditionally, so the
body this ticket quotes is unchanged and the ticket reads as if it should still
trap. It does not, because a frozen string no longer REACHES that op:
`compiler/ir.inc`'s SetLength lowering routes `IR_SETLEN_STR` only for a
managed `tyAnsiString` target, with the comment *"Only tyAnsiString reaches
here; frozen inline strings take the -101 store-length path."* The emitter was
never given the frozen arm the ticket asks for; the caller stopped calling it.

So the diagnosis in this ticket is correct about the emitter and stale about
the route. Left as a record of both, since the emitter is still a live trap for
anyone who reintroduces a frozen caller.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit a50671107.

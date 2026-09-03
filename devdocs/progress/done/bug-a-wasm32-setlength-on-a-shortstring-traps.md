---
slug: bug-a-wasm32-setlength-on-a-shortstring-traps
track: A
prio: 60
type: bug
status: done
blocked-by: []
found: 2026-09-02
found-by: frankC
owner: frankB
summary: "CAUSE KNOWN (frankwasm): WasmEmitSetLenStr unconditionally calls the managed-string RTL routine PXXStrSetLen with the slot address -- there is NO frozen arm at all, so this is a MISSING FEATURE failing loud, not a width bug, and it is unaffected by the phase-2 conversion in either direction. SetLength on a shortstring traps on wasm32 (`wasm trap: unreachable`, rc=134). Correct on riscv32 and x86-64; reproduced under the PINNED compiler, so it predates the phase-2 shortstring work. This is the cause of three of the five rows excluded from test-wasm32 -- test_cross_sets, test_frozen_string_cross_b305 and test_static_string_literal all die at 134 through this path, so it is not a corner case reached only by a probe."
---

# SetLength on a shortstring traps on wasm32

## Repro

```pascal
type TS = string[8];
var s: TS;
begin s := 'abcde'; SetLength(s, 1); WriteLn('len=', Length(s)); end.
```

```
wasm32   wasm trap: unreachable   rc=134
riscv32  len=1
x86-64   len=1
```

## Why it is worth a ticket rather than a note

Three real suite tests reach it — `test_cross_sets`,
`test_frozen_string_cross_b305`, `test_static_string_literal` — all rc=134.
It is on the ordinary path, not a shape only a probe produces.

## Controls already run

- PINNED compiler reproduces -> predates phase 2 and any local tree.
- riscv32 and x86-64 correct -> wasm32-only.

## Cause (frankwasm, 2026-09-02)

`WasmEmitSetLenStr` unconditionally calls `PXXStrSetLen` -- the managed-string
RTL routine -- with the slot address. There is no frozen arm. So the fix is to
add one, not to adjust a width: this is a missing feature that fails loudly,
which is the good kind, and it is orthogonal to the byte-prefix work.

## Related

[[bug-a-wasm32-shortstring-comparison-is-wrong-at-every-length]] — found in the
same sweep, same layout, also a reader rather than a writer. Worth checking
whether one cause covers both before fixing either.

`compiler/ir_codegen_wasm32.inc` was under active edit by frankwasm (phase-2
byte-prefix conversion) when this was filed, so it was filed rather than fixed
— topic collision, not lack of authority.

## Resolution (2026-09-03, frankB)

**The recorded cause was the plausible neighbour, not the path.**
`WasmEmitSetLenStr` calling the managed `PXXStrSetLen` with an inline buffer is
a real hazard in that procedure and **a frozen `SetLength` never reaches it**:
it is builtin `-101` (an IR_CALL with a negative proc index), and this backend
simply had no arm for it, so the body was emitted as `unreachable`. An arm added
to `WasmEmitSetLenStr` is dead code — I wrote one, measured that it never fires,
and removed it.

The backend's own diagnostic had it right all along and was one line away from
the reader: `main$0 — builtin SetLength on a frozen string (IR_CALL with proc
index -101)`.

**Same missing arm as riscv32 and xtensa** (a3c26785f, filed as riscv32-only).
Three backends, one absent `-101` arm each, three unlike symptoms: a
bare-metal-stage-1 refusal, a no-arm refusal, and a wasm trap. The fix is the
same shape in all three and names no prefix width — `WasmFrozenStoreLen` owns
it, so the arm is correct in both modes.

Verified: local, global, by-value param, by-ref param and SetLength-to-0 give
identical output on all seven targets in both modes. Positive control: arm
reverted, rebuilt, `rc=134` returns.

### The three excluded suite rows this ticket named

**Two of the three claims were wrong, and measuring them is what showed it.**
With the `-101` arm both absent and present, `test_cross_sets` reports
`value IR op 33` and `test_static_string_literal` reports `string operand of
type QWord` — unchanged, so SetLength was never their blocker. The coverage
report prints ONE refusal per body and the first one wins, which is how three
unrelated causes collected under one exit code.

`test_frozen_string_cross_b305` did go from rc=134 to matching its x86-64 twin
byte for byte — via the COMPARISON fix, not this one. It is wired now, along
with `test_char_into_shortstring_via_pointer` (rc=3 → green).
`test_write_string_field_width_cross` was already green before either fix; the
exclusion list was stale about it.

[[bug-a-wasm32-shortstring-comparison-is-wrong-at-every-length]]

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

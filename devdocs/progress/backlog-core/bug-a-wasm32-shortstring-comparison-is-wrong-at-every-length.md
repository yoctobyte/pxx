---
slug: bug-a-wasm32-shortstring-comparison-is-wrong-at-every-length
track: A
prio: 60
type: bug
status: open
blocked-by: []
found: 2026-09-02
found-by: frankC
owner:
summary: "On wasm32 ONLY, comparing a frozen string against another frozen VARIABLE is false; comparing against a LITERAL is correct. Isolated by frankwasm to operand selection in WasmStrParts -- literal and variable operands take different arms and the variable arm is wrong. NOT a width bug and NOT about parameters: two plain globals reproduce it with no parameter anywhere. Reproduced under the PINNED compiler, so it predates the phase-2 conversion; correct on riscv32 and x86-64. The slug says 'at every length', which was my original mischaracterisation -- length is not the variable."
---

# wasm32 frozen-string comparison: the VARIABLE operand arm is wrong

**The slug and my first framing are both wrong and are kept only so citations
resolve.** I filed this as "wrong at every length" with a `const lit`
parameter repro. frankwasm isolated it properly:

```
                 wasm32     native
global/global      BAD        OK      <- no parameter anywhere
global/lit         OK         OK      <- the discriminator
const param        BAD        OK
value param        BAD        OK
var param          BAD        OK
```

**Length is not the variable and parameter-ness is not the variable.** The
variable is literal-vs-variable OPERAND. My `const lit: string[8]` repro would
have sent a reader into `ABIParamSlotHoldsValueAddr` and the param-slot deref,
which is not where this lives.

## Cause (frankwasm)

Comparison reaches the prefix through `WasmStrParts`. Literal operands and
variable operands take different arms there; the variable arm is the broken
one. **It is an operand-SELECTION bug sitting on the width path, not a width
bug** — after frankwasm's conversion `WasmStrParts` reads a shortstring's one
byte and a tyString's eight correctly, and this still reproduces.

## Controls

- PINNED compiler shows the identical BAD pattern (`1eec4dc5e0a74c69`) →
  predates the phase-2 conversion and predates any local tree.
- riscv32 and x86-64 correct → wasm32-only.
- `git diff HEAD -- lib/` clean when the pinned control ran.

## Two traps for anyone re-probing this (via the coordinator)

- A literal **the same length as the string's capacity** passes for the wrong
  reason — the width-0 lesson: the expected value collides with the failure value.
- **FALSE is the generous failure shape.** A wrong prefix width yields a length
  in the billions, the length mismatch short-circuits before any character is
  compared, so it never crashes and never prints garbage. It quietly answers no.
  Anything waiting for a visible symptom will miss it.

## Distinct from the x86-64/arm32 comparison bug

`s = 'hello'` fails on exactly x86-64 and arm32 (frankh-15, under
`-dPXX_SHORTSTRING`) — a LITERAL comparison, which is the row that PASSES here.
Different partition, so presumed different cause. See
[[bug-a-frozen-compare-operand-decomposition-is-per-backend]].

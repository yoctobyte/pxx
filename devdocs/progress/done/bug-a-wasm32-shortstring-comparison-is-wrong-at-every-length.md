---
slug: bug-a-wasm32-shortstring-comparison-is-wrong-at-every-length
track: A
prio: 60
type: bug
status: done
blocked-by: []
found: 2026-09-02
found-by: frankC
owner: frankB
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

## WIDTH IS NOT THE MECHANISM HERE — do not record it as settled

frankb-a9's width explanation is correct for x86-64/arm32 (variable-vs-literal
IS the cross-width pair there: a literal keeps its 8-byte pool prefix while a
`string[N]` goes narrow under the flag) and its width-only fix turned all six
shapes green on both. **It does not transfer to wasm32.** frankwasm measured, at
HEAD with the walker fix in, at DEFAULT with no flag:

```
wasm32:  sizeof(TS) 18   var_var FALSE   var_lit TRUE   lit_lit TRUE
native:  sizeof(TS) 18   var_var TRUE    var_lit TRUE   lit_lit TRUE
```

`SizeOf 18` = cap 10 + 8, so **the variable carries the same 8-byte prefix the
literal does — there is no narrow kind anywhere in that program.** The failing
pair and a passing pair are both same-width, so prefix width cannot be what
separates them.

Two further measured facts:
- The walker fix `764dc3a30` is present and `var_var` is still FALSE. That is a
  clean separation, not residue and not a gap in that fix.
- The **pinned** compiler shows a byte-identical pattern with no flag at all, so
  this is pre-existing and must not be blocked behind the byte-prefix work.

Both frankb-a9 and frankwasm flagged this themselves rather than letting it
settle here. A wrong settled cause is more expensive than an open one.

## Distinct from the x86-64/arm32 comparison bug

`s = 'hello'` fails on exactly x86-64 and arm32 (frankh-15, under
`-dPXX_SHORTSTRING`) — a LITERAL comparison, which is the row that PASSES here.
Different partition, so presumed different cause. See
[[bug-a-frozen-compare-feeds-inttotypekind-where-irstrtkof-is-required]].

**Both sentences above are superseded, 2026-09-02, and left in place because
the reasoning from them is still sound.** The link previously named
`bug-a-frozen-compare-operand-decomposition-is-per-backend`, a ticket that was
never filed because the slug encodes an INFERENCE that turned out wrong — mine,
from this partition. There are two causes, not one, and neither is a missing
operand decomposition: arm32 HAS the width-aware layer and merely passed the
wrong kind expression, and x86-64 does not call `PXXStrEq` at all. Both are
fixed and both compare green now, so the partition this paragraph reasons from
no longer exists either. **A partition is evidence that causes differ, never
evidence of what they are** — which is exactly the step the dead slug took.

## Resolution (2026-09-03, frankB)

**The cause is neither "at every length" nor `WasmStrParts` operand selection.
It is that the predicate deciding whether a binop is a string operation asked
for the type of the VALUE each operand produces — and a frozen string's value IS
an address.** `WasmNodeResultType` answers tyPointer for IR_LEA / IR_FIELD /
IR_INDEX, correctly, so `a = b` on two `string[8]` variables reached
`WasmEmitBinop` as two pointers and compiled to an **i32.eq of two addresses**.
`WasmStrParts` was never entered; the operand-selection arms in it are fine.

The failing partition in this ticket is explained by the OR in that predicate:
a literal is tagged tyString on its own node, so `a = 'lit'` fired on the
literal side and was correct, and every frozen-vs-frozen pair silently compared
addresses.

Read off `wasm2wat`, which is the instrument that settled it — the emitted body
is `i32.const 2140472 / i32.const 2140488 / i32.eq`, two global addresses, no
call to `PXXStrEq` at all.

### The four wrong answers, because no single row catches them

| row | wasm32 before | correct |
| --- | --- | --- |
| `a = b`, equal contents | FALSE | TRUE |
| `a = a` | TRUE | TRUE — *the addresses ARE equal* |
| `a < b`, equal contents | TRUE | FALSE — *one address is lower* |
| `p^ = a` where `p := @a` | TRUE | TRUE — *same address, right answer, wrong reason* |

The failure VALUE is not constant, so a must-be-TRUE suite catches half and a
must-be-FALSE suite the other half. The last row is the repro trap: pointing `p`
at the variable you compare against makes the broken path print the right
answer.

### The fix

`WasmCompareOperandType` — the operand type a COMPARISON sees, which is not the
type its value has. It reads the IR's own tag and widens the answer only when
that tag already NAMES a string, so it can classify nothing the IR did not:
`a` lowers to a LEA tagged tyString and `@a` to a LEA tagged tyPointer over the
SAME symbol. Reading the symbol instead — what `WasmStrTypeOf` does, correctly,
to recover a prefix WIDTH — cannot tell those apart and would turn `@a = @b`
into a comparison of characters. `@a = @b`, `@a = @a` and `p = q` are asserted
for exactly that reason.

`WasmStrTypeOf` also gained the deref shape: `p^` is an IR_LOAD_SYM whose value
is the buffer address, so the existing arm answered about `p` (tyPointer) and
the operand was refused as `string operand of type Pointer` the moment the
predicate started admitting it. The node's own tag says tyString and the
existing refinement turns that into the width via `IRFrozenKindOfAddr`'s
PtrElemTk arm — the one that ticket comment predicted wasm32 would inherit.

### Verified

`test/test_frozen_compare_operand_shapes.pas`, new: every spelling on either
side (var, field, element, deref, AnsiString, literal, self), each with its
negative partner, plus ordering and the three pointer rows. Byte-identical
output on native, arm32, aarch64, riscv32, xtensa (both ABIs) and wasm32, in
both modes, **and byte-identical to FPC 3.2.2**.

Positive control: with the fix reverted and the compiler rebuilt, all ten
frozen rows return to FALSE.

Two rows are NOT wired and both are REGRESSIONS this file found, unrelated to
wasm32 and correct at pin v401:
[[bug-a-i386-comparing-two-elements-of-an-array-of-frozen-strings-is-false]]
and
[[bug-a-a-frozen-string-compared-to-an-ansistring-is-false-under-the-flag-on-x86-64]].

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit a30556172.

---
track: P
prio: 70
type: bug
found: 2026-09-02
found-by: frankB
owner: frankB
summary: "A `string[N]` ELEMENT keeps its N in a plain var array and loses it in three other containers, silently and with a wrong VALUE each time. (1) `inner: array[0..1] of string[10]` as a RECORD FIELD strides 264 bytes instead of 18 -- 264 is DEFAULT_STR_CAP+8 padded, so the declared 10 was dropped and the default substituted; SizeOf(nest.inner) says 36, correctly, so SizeOf and LAYOUT disagree by 7x on one declaration. (2) an OPEN ARRAY parameter has the RIGHT stride (18) and still reads a[2] as empty, so this one is NOT the same cause. (3) `array of array of string[10]` returns a corrupted element. All three reproduce on the PIN, so none is from the 2026-09-02 SizeOf work; FPC 3.2.2 gets all three right. Named lead for (1): UFldStrCap holds the FIELD's own capacity and ir.inc:11260 reads it as the ELEMENT's."
status: working
---

# A `string[N]` element keeps its capacity in one container and loses it in three

## Measured

Same declaration in four containers, `pxx` at `d830b2c56`, oracle `fpc -O- -Mobjfpc` 3.2.2:

| shape | stride pxx | stride fpc | value |
| --- | ---: | ---: | --- |
| `var oa: array[0..2] of string[10]` | 18 | 11 | correct |
| `record inner: array[0..1] of string[10]` | **264** | 11 | correct here, but see below |
| `const a: array of string[10]` (open array) | 18 | 11 | **`a[2]` empty** |
| `array of array of string[10]` | — | — | **element corrupted** |

18 is right for pxx (`FrozenStrSlotSize` = cap+8); FPC's 11 is cap+1, which is
the separate representation question and NOT what this ticket is about. The
defect is 264, and the two wrong values.

**264 is `DEFAULT_STR_CAP + 8` padded** (255+8 = 263 -> 264). So the declared
`10` was not merely mis-sized, it was **dropped**, and the "no capacity
recorded" default substituted.

`SizeOf(nest.inner)` answers **36** — 2 x 18, correct for the declaration —
against a real stride of 264. One declaration, two sizing paths, disagreeing by
more than 7x. Same class as
[[bug-p-sizeof-answers-pointer-width-for-a-string-n-that-occupies-more]] with the
arms swapped: there SizeOf was wrong and layout right, here layout is wrong and
SizeOf right. That is the argument for the umbrella's one-oracle end condition
rather than a fix on either side.

## Not from the SizeOf work, and not one cause

All three reproduce on `stable_linux_amd64/default/pinned`, which predates the
2026-09-02 `SizeOfSlot` change. That change *improved* two rows here
(`SizeOf(cls.f)` 8 -> 18, `SizeOf(nest.inner)` 16 -> 36) and moved no stride.

**They are at least two causes, and the ticket should not be closed on one.**
The open-array parameter has the CORRECT stride of 18 and still reads `a[2]`
empty, so whatever loses the capacity in (1) is not what breaks (2). Verified
by measuring the stride from inside the callee.

## Lead for (1)

`ir.inc:11260` sizes a record array field's element with
`FrozenStrSlotSize(UFldTk[faFldIdx], UFldStrCap[faFldIdx])`, and `UFldStrCap`
holds **the field's own** capacity, not its element's. For
`inner: array[0..1] of string[10]` the field is an array, so its own capacity is
0, and `FrozenStrSlotSize` maps 0 to `DEFAULT_STR_CAP` — which is exactly 264.

This is a shape the codebase already knows about twice: `ArrTypeElemStrCap`
exists because `AliasStrCap` could not also hold the element's, and
`SymPtrElemStrCap` exists because `SymStrCap` could not — its `defs.inc` comment
says so and cites the bug where `p^[1]` read at the wrong offset. The record
field table is the third instance and has no `UFldElemStrCap`.

`pasparser_decl.inc` already threads a local `aElemStrCap` from
`ArrTypeElemStrCap` for a NAMED array element type, which suggests the named
spelling may behave differently from the inline one — worth measuring both
before fixing, since that is the double-case shape this repo keeps hitting.

## Gate

`make test` + self-host + cross. Strides are ABI. Assert the STRIDE directly and
in each of the four containers: a value-only test passes on every element that
fits inside the mis-sized slot, which is why a 7x layout error has been sitting
under a green suite. Include the plain-var row — it is the one that works, and a
fix that "corrects" it has over-reached.

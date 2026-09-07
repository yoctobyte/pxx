---
slug: bug-a-two-dozen-comments-describe-an-interface-value-as-a-16-byte-fat-pointer-and-it-is-one-pointer
track: A
prio: 25
type: bug
blocked-by: []
status: backlog
found: 2026-09-07
found-by: frankS
owner: unassigned
summary: "About two dozen comments across compiler/** say an interface VALUE is a 16-byte fat pointer {IMT, instance}. Measured 2026-09-07: it is ONE pointer, the instance, 8 bytes on x86-64 under both pxx and fpc 3.2.2 -- UClsSize_ is TARGET_PTR_SIZE at the interface parse site and AN_INTF_CALL recovers the IMT per call via PXXIntfIMTOf. The AN_INTF_CALL lowering carries BOTH claims in adjacent lines. Not a wrong answer today; it is a wrong map, and it already misled one change."
---

# Two dozen comments describe an interface value as a 16-byte fat pointer, and it is one pointer

## The fact

`grep -n 'fat pointer' compiler/*.inc` returns ~28 hits. Many describe an
interface value as **a 16-byte fat pointer `{IMT, instance}`**. The code does not
do that.

Measured 2026-09-07 at compiler `5e0e74000eea`:

```
SizeOf(IFoo var) = 8     pxx
SizeOf(IFoo var) = 8     fpc 3.2.2
SizeOf(Pointer)  = 8
```

Two independent places in the compiler say the same thing:

- `pasparser_decl.inc`, at the interface's own parse site — `UClsSize_[ci] :=
  TARGET_PTR_SIZE;` with a comment spelling it out: *"An interface VALUE is ONE
  pointer — the instance (FPC's ABI) ... The IMT is recovered per call from the
  instance's RTTI blob by interface id."*
- `ir.inc`, the `AN_INTF_CALL` lowering — `Self = [iface]` (a single
  `IR_LOAD_MEM` at offset 0) and `imt := PXXIntfIMTOf(self, intfCi)`.

**The clearest evidence is that `AN_INTF_CALL` contradicts itself in adjacent
lines.** The block header says *"the interface value is a fat pointer {IMT@0,
instance@8}"* and the very next comment line says *"An interface value is ONE
pointer: the instance."* One of them was updated when the representation changed
and the other was not.

## Why it is worth a ticket rather than a sweep

**Because a blind `sed` would be wrong.** "Fat pointer" is also the correct term
for things in this compiler that really are two words — a **method pointer**
(`{code, data}`), which is what several of those hits are about
(`pasparser_lval.inc:3317`, `pasparser_expr.inc:1563`, the `pyparser.inc` pair).
`pasparser_proc.inc:2813` reasons about parameter passing from *"on 64-bit that
is 16 bytes (already >8)"* — if that is about interfaces it is reasoning from a
false premise and the conclusion needs re-checking, not the comment.

So this needs someone who owns the representation to go hit by hit and decide,
for each, which thing it is talking about. That is coordination, which is what a
ticket is for.

## It has already cost something

Fixing for-in over an interface enumerator (`47b4c7c82`'s follow-up), I read
`defs.inc:6318` and **propagated the false claim into three new comments**,
including one asserting the crash happened because the lowering *"pushed the fat
pointer's IMT word as Self"*. It did not. The real mechanism is that
`UMthVirSlot` means a **vtable index** for a class method and an **IMT slot** for
an interface method, and the copied dispatcher emitted an `AN_VIRTUAL_CALL` that
indexed the instance's vtable with an IMT slot number. **Same crash, wrong story**
— and the wrong story is the one that would have been quoted next time.

## What to check

- `defs.inc:6318` (`UClsIsInterface`) and `defs.inc:6349` — the two that a reader
  looking up the type will find first.
- `ir.inc:16052` — the self-contradicting pair; delete the stale half.
- `ir.inc:270`, `:13758`, `:13804`, `:13981`, `pasparser_decl.inc:1334`, `:7080`,
  `pasparser_proc.inc:192`, `:2813`, `pasparser_expr.inc:319`, `:10788`,
  `symtab.inc:3933` — each to be read for which object it means.
- Leave the method-pointer hits alone; they are correct.

## How you would know it is done

`grep -n 'fat pointer' compiler/*.inc` returns only hits about method pointers
and COM/ARC record aggregates, and `SizeOf` of an interface variable is asserted
somewhere — there is no test today that pins it at all, which is why the drift
was invisible.

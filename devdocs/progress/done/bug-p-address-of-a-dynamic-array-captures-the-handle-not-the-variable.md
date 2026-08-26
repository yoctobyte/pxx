---
summary: "`@dy` on a dynamic array yields the HANDLE, not the address of the variable, so a ^TDyn pointer goes stale on any reallocation and reads a freed buffer"
type: bug
track: P
prio: 55
---

# `@dy` yields the handle, so a pointer to a dynamic array goes stale

**RESOLVED 2026-08-26.** `@` on a dynamic array now yields the variable's slot,
the same correction managed strings already had. See Outcome at the end.

- **Type:** bug (Pascal frontend / address-of lowering) — **Track P**, but the
  lowering is in shared ground, so it obeys Track A's gate.
- **Found:** 2026-08-26, while fixing
  [[bug-p-length-of-a-pointer-to-a-dynamic-array-answers-one]]. It is the reason
  that fix had to be measured rather than reasoned: every plausible lowering of
  `Length(p^)` segfaulted until the probe below showed why.

## Measured

```pascal
type TDyn = array of LongWord; PDyn = ^TDyn;
var dy: TDyn; pdy: PDyn;
begin
  SetLength(dy, 5);
  pdy := @dy;
  WriteLn(PtrUInt(pdy) = PtrUInt(Pointer(dy)));   { is @dy the HANDLE? }
end.
```

| | `@dy = handle` | `@dy = @dy[0]` |
| --- | --- | --- |
| fpc 3.2.2 | **False** — `@dy` is the variable's slot | True |
| pxx | **True** | True |

In pxx all three of `@dy`, `Pointer(dy)` and `@dy[0]` are the same address.
In fpc `@dy` is a small slot address and the other two are the heap buffer.

## Why it matters — it is a stale pointer, not a cosmetic difference

`p` captures the buffer that existed at `@`-time. Reallocate and `p` still
points at the old one, which `SetLength` may already have freed:

```pascal
  SetLength(dy, 5);  pdy := @dy;
  SetLength(dy, 9);
  WriteLn(Length(pdy^));      { fpc: 9    pxx: 5, off the OLD buffer }
```

That read is a use-after-free in every case where the reallocation moved the
block. It is silent and it compiles clean. The same capture makes `pdy^ := other`
and `SetLength(pdy^, n)` unable to rebind the variable at all — there is no
variable on the other end of the pointer to rebind.

## Why it was invisible until now

`Length(pdy^)` used to answer a constant 1 (the bug above), so nothing that
could observe staleness ever ran. Fixing Length is what made this reachable.

## The precedent, and the shape of the fix

**Managed strings already went through exactly this and were corrected.** See
the `Length(ps^)` arm in `compiler/ir.inc` (~11003), whose comment records the
change verbatim: *"`@s` now yields the address of the VARIABLE (its slot), which
is what @ means and what makes `ps^` readable and writable at all."* Dynamic
arrays are the same concept — a managed handle in a slot — and did not get the
same correction. This is a `normalise-dont-special-case` item: one rule for what
`@` means over a managed value, not one per managed type.

The catch that makes it more than a one-liner: `pdy^[i]` currently works
*because* `pdy` is the data pointer, so the index path lands on elements
directly. Moving `@` to the slot must move the deref path in lockstep, and
`Length(p^)`'s lowering (which now reads `p`'s value as the handle) flips back
to the load-from-slot form the string arm uses. Do them together or the suite
goes red in three places.

## Gate

`make compiler/pascal26` + the probe above diffed against fpc + `tools/gate.sh
quick`. `test/test_pointer_to_a_named_fixed_array.pas` documents the divergence
in its header and deliberately does not assert it; that comment comes out when
this lands, and the post-`SetLength` row goes in.


---

## Outcome (2026-08-26)

Fixed as the ticket framed it: one rule for what `@` means over a managed value.
`@dy` on a dyn-array ident lowers to `IR_SLOTADDR` -- the same node `@s` on a
managed string was given -- instead of `IR_LEA`, whose backends deliberately
auto-load the handle for both kinds.

The ticket warned that the deref path had to move in lockstep or three things
would go red. Measuring first showed the lockstep was cheaper than feared,
because two of the three were ALREADY broken and nobody had noticed -- the
ticket's own claim that `pdy^[i]` "currently works because pdy is the data
pointer" did not survive the probe:

| through `pd: PDyn` | fpc | pxx before | pxx after |
| --- | --- | --- | --- |
| `PtrUInt(pd) = PtrUInt(Pointer(dy))` | FALSE | **TRUE** | FALSE |
| `Length(pd^)` after `SetLength(dy, 9)` | 9 | **5**, off the old buffer | 9 |
| `pd^[0]` | 42 | **0** | 42 |
| `pd^[1] := 7` | writes dy[1] | **wrote past it** | writes dy[1] |
| `pd^ := other` | rebinds dy | **segfault** | rebinds dy |

Three changes, all forced by the first:

1. `IRLowerAddress`'s `AN_ADDR` arm: `IR_SLOTADDR` for a dyn-array ident.
2. `Length(p^)`: the arm's comment used to explain, at length, that p already WAS
   the handle so any load would go one level too far. That premise is gone, so it
   loads the handle out of the slot -- textually the same shape the string arm
   adopted when it made this move, and its comment records the same 0-length
   symptom for skipping it.
3. `p^[i]`: `AN_DEREF` joins `AN_INDEX`/`AN_FIELD` on the `IR_DYNUNIQUE` path.
   p's value IS the handle slot, which is what that path wants; the plain depth-1
   path below it addresses a variable's slot directly and had nothing to address.

Pinned in `test/test_pointer_to_a_dynamic_array.pas`, including the managed-string
rows -- the point of the fix is that the two now answer the same way, so pinning
only the array half would not show it. The divergence note in
`test/test_pointer_to_a_named_fixed_array.pas` is replaced by a pointer to that
file; its BORROWED-ownership rows stay, and they are what proves the fix was not
paid for with a use-after-free.

## What is NOT fixed, and why

`SetLength(p^, n)`. fpc accepts it. It used to reach codegen misclassified as a
STRING target and die on `SetLength expects a string variable in IR codegen`,
which describes neither the program nor the limitation; it is now refused in the
parser with a message that names the restriction and the workaround.

Not a lowering gap a line would close: the dyn-array `SetLength` codegen is
symbol-based end to end -- it emits `[rbp+off]` or a global ref from the target's
symbol INDEX -- so an address target means a second variant in all six backends.
That is its own piece of work. Everything else through a `^TDyn` works, so the
workaround is one line: resize the variable, or pass it as a `var` parameter,
which is the resizable-by-reference form pxx does support.

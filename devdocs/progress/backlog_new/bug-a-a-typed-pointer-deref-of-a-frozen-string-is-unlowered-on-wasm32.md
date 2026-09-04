---
track: A
prio: 25
type: bug
blocked-by: []
summary: "Reading through a typed pointer to a frozen string — Length(p^) where p: ^string[10] — is unlowered on wasm32 and traps with `wasm trap: unreachable`, at DEFAULT as well as under -dPXX_SHORTSTRING. The WRITE through the same pointer (p^ := c) lowers fine, so this is a missing read lowering, not a pointer problem. Confirmed under the pinned compiler, so it predates the byte-prefix conversion. Consequence for another lane: wasm32 cannot go green on any Length(p^) row, so it must not be counted as a target for the IRFrozenKindOfAddr read-side fix."
status: new
owner: ""
---

# `p^` on a frozen string is unlowered on wasm32 (read side only)

Found 2026-09-02 by the wasm32 lane while landing the tyShortString byte-prefix
conversion (`0973746b0`). **Not caused by it** — see the control below.

## Repro

```pascal
program deref;
type TS = string[10]; PS = ^TS;
var s: TS; p: PS;
begin
  s := 'hello'; p := @s;
  WriteLn('Length(s)  ', Length(s));
  WriteLn('Length(p^) ', Length(p^));
end.
```

| build | default | `-dPXX_SHORTSTRING` |
| --- | --- | --- |
| native x86-64 | `5` / `5` | `5` / `122511465736197` |
| wasm32 (wasmtime) | **trap: unreachable** | **trap: unreachable** |

The native `-dPXX_SHORTSTRING` number is a *different, known* defect
(`IRFrozenKindOfAddr`, frankb-a9's) and is only in the table to show the two are
not the same thing. wasm32 never reaches that question.

## The control that makes this pre-existing rather than mine

The same program, same target, compiled with
`stable_linux_amd64/default/pinned` (`1eec4dc5e0a74c69`), traps identically at
default. The conversion changed nothing here in either direction.

## Why the WRITE side is not part of this ticket

`p^ := c` through the same pointer **does** lower on wasm32. It is wrong under
`-dPXX_SHORTSTRING`, but for the unrelated shared-walker reason, and that half
is tracked with the walker. Precisely:

```
p^ := c    with c = 'X', under -dPXX_SHORTSTRING, bytes at @s
native  : 255 0 0 0 0 0 0 0 0 0 0
wasm32  :   1 0 0 0 0 0 0 0 88 0 0     { 'X' at offset 8, not 1 }
```

So the two directions have different causes and only the read one is a wasm32
lowering gap. **Do not fix them together.**

The write half is a defect `0973746b0` **exposes, not introduces**. It created a
new caller of `IRFrozenKindOfAddr` (`WasmEmitStoreMem` asks it for the
destination kind), and that function answers tyString for a `p^` destination, so
the backend does the wide thing correctly with a wrong answer. Nothing in that
commit's own acceptance set routes through a typed-pointer deref — the 8/8
oracle matrix, the 35/35 byte-identity and its positive control are all
unaffected — which is why the conversion was not re-verified over it.

**The wasm32 corruption differs from native's while sharing the cause**, and
that is useful rather than confusing: a fix that turns both into `1 88` is
checkable on two shapes instead of one. Note also that wasm32's is the quieter
of the two — the low byte of the 8-byte word reads back as a correct
`Length` of 1 — so a fix asserting on `Length` passes while still broken.

## Method note, because this ticket was nearly filed with the opposite claim

The first version of this finding said wasm32 did **not** acquire the walker
defect. The read side had been measured, and the sentence "the shape never
reaches the width question" was allowed to cover a write that had not been. It
was load-bearing for two minutes: another lane's fix was scoped to six targets
on it before the correction landed.

The reusable part is not "measure both directions". It is that **a mechanism
sounds like it generalises and an absence does not** — so reporting the bare
absence would have been SAFER here than reporting the correct why for half the
shape. A `why` invites the reader to extend it; a `didn't see it` does not. When
you have a mechanism for part of a shape, name the part.

## The consequence that matters to someone else

`IRFrozenKindOfAddr`'s read-side fix cannot turn wasm32 green on a `Length(p^)`
row — wasm32 traps before the width is consulted. A matrix that expects seven
green targets on that row will read wasm32's trap as the fix failing. wasm32 IS
a site for the WRITE-side half of that fix; it is not one for the read half.

## A SILENT SIBLING WITH THE SAME CAUSE, found 2026-09-04

`bug-a-wasm32-a-frozen-string-through-a-pointer-in-a-record-field-compares-as-the-fields-address`.
`r.NamePtr^ = 'lit'` for `NamePtr: ^string[N]` in a RECORD FIELD answers FALSE
on wasm32 and TRUE on the other five targets — no gap, no trap, and the same
expression PRINTS the string correctly. It is why `GetClass` returns nil on
wasm32.

So the p25 rating's premise — "fails loud and produces no wrong value" — is
true of THIS ticket's shape and not of the cause. Read the sibling before
scoping a fix: the closing paragraph below says the address-is-the-value arm is
"right for a `string[N]` record field", which holds only when the field IS the
string and is exactly wrong when the field HOLDS A POINTER to one.

## Where it is

The trap is a `WasmUnsupported` (`unreachable`), so it fails loud and produces
no wrong value — which is why this is p25 and not higher. Whoever takes it
should start at `WasmEmitLoadMem` in `compiler/ir_codegen_wasm32.inc`: it has a
`TypeIsFrozenString` arm that treats the address as the whole value, which is
right for a `string[N]` record field and is not what a `^TS` deref needs.

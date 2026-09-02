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

## The consequence that matters to someone else

`IRFrozenKindOfAddr`'s read-side fix cannot turn wasm32 green on a `Length(p^)`
row — wasm32 traps before the width is consulted. A matrix that expects seven
green targets on that row will read wasm32's trap as the fix failing. wasm32 IS
a site for the WRITE-side half of that fix; it is not one for the read half.

## Where it is

The trap is a `WasmUnsupported` (`unreachable`), so it fails loud and produces
no wrong value — which is why this is p25 and not higher. Whoever takes it
should start at `WasmEmitLoadMem` in `compiler/ir_codegen_wasm32.inc`: it has a
`TypeIsFrozenString` arm that treats the address as the whole value, which is
right for a `string[N]` record field and is not what a `^TS` deref needs.

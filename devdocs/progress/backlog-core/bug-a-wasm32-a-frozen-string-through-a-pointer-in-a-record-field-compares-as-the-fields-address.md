---
slug: bug-a-wasm32-a-frozen-string-through-a-pointer-in-a-record-field-compares-as-the-fields-address
track: A
prio: 60
type: bug
status: open
blocked-by: []
owner: unassigned
created: 2026-09-04
found-by: frankA (closing IR_RTTI_REG on wasm32)
summary: "On wasm32 `r.NamePtr^ = 'lit'` is FALSE where every other target says TRUE, for `NamePtr: ^string[N]` held in a RECORD FIELD. The field's own ADDRESS is used as the frozen string's address -- the pointer is never LOADED -- so the compare reads the pointer value as the length and the bytes after it as the chars. Through a plain pointer VARIABLE the identical expression is correct. SILENT: no gap, no trap, the string PRINTS correctly through the same expression; only the comparison is wrong. It is why GetClass returns nil on wasm32 and therefore why test_metaclass_getclass is the one metaclass test still not wired for this target."
---

# wasm32: a frozen string through a pointer in a record field compares as the field's address

## Repro, 20 lines, all six targets

```pascal
program probe8;
type
  S256 = string[256];
  P256 = ^S256;
  TEnt = record NamePtr: P256; other: Pointer; end;
var n2: S256; r: TEnt; q: P256;
begin
  n2 := 'TDer';
  r.NamePtr := @n2;
  q := r.NamePtr;
  WriteLn('plainvar ', q^ = 'TDer');          { TRUE everywhere }
  WriteLn('field    ', r.NamePtr^ = 'TDer');  { TRUE except wasm32 }
end.
```

x86-64, i386, arm32, riscv32, xtensa: both TRUE. wasm32: `plainvar` TRUE,
`field` FALSE. Also FALSE through `arr[i].NamePtr^`, `e^.NamePtr^` and
`e[i].NamePtr^` — every shape whose pointer comes from a field. **The boundary
is the FIELD, not the index and not the deref.**

## What the module actually does

`wasm2wat`, the two compares side by side:

```
q^ = 'TDer'                      r.NamePtr^ = 'TDer'
  i32.const <addr of q>            i32.const <addr of r>
  i32.load        <-- the ptr      local.set 6          <-- NO LOAD
  local.set 6
  local.get 6; i32.load            local.get 6; i32.load        (reads the POINTER as the length)
  local.get 6; i32.const 8; add    local.get 6; i32.const 8; add (reads r+8 as the chars)
```

A frozen string operand evaluates to its ADDRESS. For `q^` the address is the
pointer's VALUE, and the load is there. For `r.NamePtr^` the lvalue address of
the field is computed and the dereference is dropped, so the compare is handed
`@r.NamePtr` where it wanted `r.NamePtr`.

## Why it is worth more than one wrong Boolean

`WriteLn(r.NamePtr^)` prints `TDer` correctly on wasm32 — the write path
dereferences. So a program can print the right string and compare it wrongly in
adjacent statements, which is the shape this repo calls expensive: no crash, no
diagnostic, a plausible wrong value far from the cause.

Its live consumer is `typinfo.pas`'s `GetClass`, whose whole body is
`entries[i].NamePtr^ = name` over the RTTI registry. On wasm32 the registry is
now reachable and correct (`__rttireg()` non-nil, `count 3`, all six pointers
right — measured), every name PRINTS correctly, and every comparison answers
False, so `GetClass` returns nil and the caller constructs from a nil header.

## Where to look

`WasmCompareOperandType` / the frozen-operand address path in
`ir_codegen_wasm32.inc`. Note `WasmEmitLoadMem`'s first arm is guarded by
`TypeIsFrozenString(tk)`; widening that guard to `tySet`/`tyRecord` was tried
and REVERTED on 2026-09-04 because an interface is spelled `tyRecord` and its
field holds a pointer that must be loaded — the two cases pull in opposite
directions and the fix has to distinguish them, not widen.

Positive control for any fix: `plainvar` must stay TRUE (it is the row that
already works and the one a "just always load" change would break).

## The sibling, and a correction to what it says to do

`bug-a-a-typed-pointer-deref-of-a-frozen-string-is-unlowered-on-wasm32`
(backlog_new, p25, filed 2026-09-02) is the LOUD half of this cause and it is
still reproducible: `Length(p^)` for `p: ^string[N]` refuses on wasm32 with
`Length of Pointer — only strings are implemented on this target so far`, seen
again today. Same arm, same lost type, two symptoms — one refuses and one
answers False — so they belong to one fix and are two tickets because a reader
looking for either symptom must find it.

**Its closing sentence is the one thing to not follow.** It says
`WasmEmitLoadMem`'s `TypeIsFrozenString` arm "treats the address as the whole
value, which is RIGHT for a `string[N]` record field and is not what a `^TS`
deref needs." The first half is true only when the FIELD IS the frozen string.
When the field holds a POINTER to one — `NamePtr: ^string[256]`, the shape
typinfo's registry is built from — the address is emphatically not the value,
and treating it as one is precisely the defect measured above. A fix scoped by
"fields are fine, typed derefs are not" would leave this bug exactly where it
is, and it would leave it in the silent half.

The distinction the fix needs is not field-versus-deref. It is **what the
operand's static type says is AT that address**: a frozen string (address is
the value) or a pointer to one (load it first).

Positive controls for any fix, both directions:
- `q^ = 'lit'` through a plain pointer VARIABLE must stay TRUE — it already
  works, and a "always take the address" change breaks it.
- a plain `string[N]` FIELD, `r.s = 'lit'`, must stay TRUE — it already works,
  and a "always load" change breaks it.

---
track: A
prio: 60
type: bug
status: done
found: 2026-09-28
found-by: frankD
owner:
summary: "LEAK and a stray free, wasm32 only. `Move(s[i], c, 1)` with a `const` string s: a by-reference argument is walked in write position, so IR_INDEX ran copy-on-write (PXXStrUnique) on s even though Move's source is `const` and only read. The clone was published into the const parameter's slot, which nobody releases. sysutils.Copy (SetLength + Move) leaked one block per call on a shared or static source; with a heap source the census went negative (live=-381 over 400 JSONParse('1') calls, measured with the static-literal change in; the tree compiler read -116 on 400 `[1,{..}]` parses). Both read flat with this fix."
---

# wasm32: a const by-ref argument clones the string it indexes

Found once string literals became static handles
(bug-a-wasm32-string-literals-are-heap-copies-so-a-const-table-stays-live):
before that change, sysutils.Copy's source was a heap temp with rc=1, so the
clone never happened. `JSONParse('[1]')` with FreeTree then leaked one block per
array element. Native builds of the same probes stayed flat.

## Resolution (2026-09-28)

Both wasm32 argument loops (the direct call and the indirect/virtual one) set
WasmConstRefArg when the by-ref parameter is `const`. WasmEmitIndex then loads
the handle from the slot instead of calling PXXStrUnique. A `var` argument
still clones.

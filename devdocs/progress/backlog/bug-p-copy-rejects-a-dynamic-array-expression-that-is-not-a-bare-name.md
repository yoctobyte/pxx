---
summary: "Copy() on a dynamic array only accepts a bare IDENTIFIER. Copy(g[0]), Copy(r.items) and their 3-argument forms are all rejected, though FPC accepts every one — so the deep-copy idiom for a nested array cannot be spelled at all."
type: bug
track: P
prio: 60
---

# `Copy` rejects any dynamic-array expression that is not a bare name

- **Type:** bug — Track P (Pascal frontend). Files: `compiler/parser.inc`.
- **Found:** 2026-08-06, restructuring `test/test_threadsafe_layout_rtti.pas`
  after the aliasing flip, where `Copy(SharedGrid[0])` was the natural fix and
  did not compile.
- **Pre-existing:** every form below is rejected by
  `stable_linux_amd64/default/pinned` too, including the three-argument ones. The
  `Copy(a)` shorthand added in `a855d1d5f` inherited the restriction rather than
  introducing it.

## Measured

```pascal
type
  TG = array of array of Integer;
  TR = record items: array of Integer; end;
var g: TG; r: TR; x: array of Integer;
...
x := Copy(g[0]);          { element of a nested array }
x := Copy(g[0], 0, 2);
x := Copy(r.items);       { record field }
x := Copy(r.items, 0, 2);
```

| form | FPC | pxx (and pinned) |
| --- | --- | --- |
| `Copy(a)` / `Copy(a, i, n)` — bare name | ✅ | ✅ |
| `Copy(g[0])` | ✅ `2 1` | ❌ rejected |
| `Copy(g[0], 0, 2)` | ✅ `2 1` | ❌ rejected |
| `Copy(r.items)` | ✅ `2 7` | ❌ rejected |
| `Copy(r.items, 0, 2)` | ✅ `2 7` | ❌ rejected |

The one-argument forms hit the shorthand's own diagnostic ("needs a DYNAMIC
ARRAY"), which is misleading here — `g[0]` *is* a dynamic array. The
three-argument forms fall through to the generic dynarray-Copy error.

## Cause

Both `Copy` lowering sites gate on the first argument being a symbol:

```pascal
if (ASTKind[exprNode] = AN_IDENT) and (ASTIVal[exprNode] >= 0) and
   Syms[ASTIVal[exprNode]].IsArray and (Syms[ASTIVal[exprNode]].ArrLen = -1) then
```

That is not an accident of the check but of the LOWERING: `AN_DYN_COPY` takes its
element metadata (element type, element size, record id, depth) from the source
**symbol**, so without a symbol there is nothing to read it from.

## Fix

The machinery to do this already exists elsewhere in the same file:
`GetOrAllocNodeDynDesc` / the `IRSetLenBaseRec` path derives exactly this metadata
from a NODE rather than a symbol, which is how `IR_SETLEN_DYN` already supports
`SetLength(r.items, n)` and `SetLength(a[i], n)` on non-symbol targets. So this is
plumbing an existing pattern into `AN_DYN_COPY`, not inventing one — mirror what
`SetLength` does for the same two shapes.

Accept any expression whose static type is a dynamic array, and take the element
metadata from the node. Both lowering sites need it (the bare intrinsic in
`ParseFactor` and the no-overload-match fallback) — they are the double case
`a855d1d5f` already had to fix once.

## Why this matters more since 2026-08-06

`Copy` is the escape hatch now that assignment aliases
(`decide-dynamic-array-value-vs-reference-semantics`). For a NESTED array the
deep-copy idiom is per level:

```pascal
local := Copy(shared);
local[0] := Copy(shared[0]);   { <-- does not compile }
```

FPC runs that and prints `shared=root local=changed`. In pxx the second line is
unspellable, so **there is currently no way to write a deep copy of a nested
dynamic array** — the escape hatch only reaches one level. That is why this is 60
rather than the 45 a plain missing-surface ticket would get.

(Note the one-level behaviour is itself correct and matches FPC:
`SetLength`/`Copy` detach ONE level and leave the sub-array handles shared —
`test/test_nested_alias.pas` asserts exactly that, verified against FPC.)

## Gate
The four forms above compiling and matching FPC's output, the bare-name forms
unchanged, `Copy(s, i, n)` on a string unchanged, and the nested deep-copy idiom
working. Then simplify `test_threadsafe_layout_rtti.pas`'s worker back to
`Copy(SharedGrid[0])`, which is what it wanted to say.

---
track: N
prio: 55
type: bug
---

# `xs += ys` on a VARIANT-typed list rebinds instead of extending, so the caller never sees it

```python
def grow(l):
    l += [9]
c = [1]
grow(c)
print(c)          # CPython: [1, 9]     pxx: [1]

vs = [[1]]
e = vs[0]
e += [5]
print(vs[0])      # CPython: [1, 5]     pxx: [1]
```

Python's `+=` on a list is `__iadd__` — IN-PLACE, so every alias sees the new
elements. pxx does the in-place lowering only when the target's type is
STATICALLY `TPyList`:

`pyparser.inc`, both augmented-assignment sites (≈10855 and ≈10963):

```pascal
if (augTk = tkPlus) and (PyNodeListCi(lhsNode) >= 0) then
  Result := PyCallMeth1(PyNodeListCi(lhsNode), 'extend', lhsNode, CurASTNode);
```

and `PyNodeListCi` gives up immediately unless the node is `tyClass`:

```pascal
if IntToTypeKind(ASTTk[n]) <> tyClass then Exit;
```

An unannotated parameter, a list out of a list, a list out of a dict — all
variants — therefore fall through to `x := x + y`, which builds a NEW list and
rebinds the local. The original object is untouched, so the mutation is simply
lost. No error, no warning.

## Measured, so the boundary is exact

Same file under CPython and pxx (`alias2.npy`):

| form | CPython | pxx |
| --- | --- | --- |
| `def grow(l: List[int])` — annotated, so `tyClass` | `[1, 9]` | `[1, 9]` |
| `def grow(l)` — unannotated, so variant | `[1, 9]` | **`[1]`** |
| `l.extend([9])` through a variant | `[1, 9]` | `[1, 9]` |
| `l.append(9)` through a variant | `[1, 9]` | `[1, 9]` |
| `e = vs[0]; e += [5]` | `[1, 5]` | **`[1]`** |
| `g = d["k"]; g += [8]` | `[1, 8]` | **`[1]`** |

So the METHODS already dispatch correctly through a variant; only the operator
form does not. Pre-existing — reproduced identically on `pinned`, not a
regression from the mixed-type operand work.

## Shape of a fix

The type is unknown at compile time, so it has to be decided at run time, the
same way the rest of the operator family now is
([[bug-nilpy-mixed-type-arithmetic-silently-does-pointer-math]]).

A helper that keeps the object identity when the target holds a list:

```pascal
function pyaugadd_v(const target: Variant; const v: Variant): Variant;
{ target holds a TPyList -> extend it IN PLACE and hand the SAME object back,
  so the surrounding `x := pyaugadd_v(x, y)` rebinds x to what it already
  pointed at and every alias sees the new elements. Anything else -> pyadd_v. }
```

Then mark the augmented `+` node in `ASTSLen` (a new `PY_BINOP_AUGADD`
alongside `PY_BINOP_IDENTITY` in `defs.inc`) at the two pyparser sites when the
lhs is `tyVariant`, and have the `ir.inc` `AN_BINOP` variant-dispatch block
pick `pyaugadd_v` instead of `pyadd_v` for a marked node. No by-reference
variant parameter is needed — extend mutates through the handle, so returning
the same object is enough.

Watch the ARC side: the returned variant must retain the way `pyor_v`'s
`PyVarSlotInit` does, or the rebind releases the object it just kept.

## Gate

`make test-nilpy` + self-host byte-identical, plus the table above re-diffed
against CPython, and `xs += ys` where the target is statically a list must
still lower to `extend` (unchanged path).

## CLOSED

Implemented exactly as suggested: `pyaugadd_v` (extends a TPyList target in
place, returns the same retained object via `PyVarSlotInit`, falls through to
`pyadd_v` otherwise), a new `PY_BINOP_AUGADD` marker set at both pyparser.inc
`+=` sites (the lhs-expression one and the bare-name one — the ticket's own
`def grow(l): l += [9]` repro goes through the SECOND, which needed the same
marker) when the target's static type is `tyVariant`, and `ir.inc`'s
variant-`+` dispatch picks the new helper when it sees the marker.

Every row in the ticket's table now matches CPython, and the statically-typed
`xs += ys` path (an annotated parameter) is unchanged — confirmed still lowers
straight to `TPyList.extend`, no new dispatch involved.

Test: test/test_nilpy_augmented_add_variant_list.npy. Gate: make test-nilpy
green, self-host fixedpoint, testmgr --tier quick.

Ticket closed.

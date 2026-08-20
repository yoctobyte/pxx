---
track: P
prio: 65
type: bug
blocked-by: []
summary: "A TYPED class const (`const X: T = ...`) is registered under its BARE name in the global namespace, not under a class-mangled key like the untyped forms are. Two classes each declaring `const TAG: array[1..2] of Integer` therefore share one storage slot: TA.Get returns TB's value. Silent wrong value, no diagnostic; FPC gets it right."
status: urgent
owner: unassigned
---

# P typed class consts of the same name in two classes collide

- **Track P** (`compiler/pasparser_decl.inc`, the class-body const arm around
  line 2010).
- Found while working v3 of [[feature-pascal-type-helpers]] (a helper's
  `const SIZED_SIGN_MASK: array[1..32] of UInt32` is unreachable by qualified
  name). The unreachability is the *documented* half; this collision is what
  was under it, and it is worse.

## Repro, diffed against FPC 3.2.2

```pascal
type
  TA = class
    const TAG: array[1..2] of Integer = (10, 11);
    class function Get: Integer; static;
  end;
  TB = class
    const TAG: array[1..2] of Integer = (20, 21);
    class function Get: Integer; static;
  end;
class function TA.Get: Integer; begin Get := TAG[1]; end;
class function TB.Get: Integer; begin Get := TAG[1]; end;
```

| | FPC 3.2.2 | pxx (7b18ddbac) |
| --- | --- | --- |
| `TA.Get` | `10` | **`20`** |
| `TB.Get` | `20` | `20` |

`TA.Get` returns `TB`'s value. No warning, no error — the two consts are one
slot, and whichever is declared last wins for both.

## Root cause — it is written down in the code already

`compiler/pasparser_decl.inc`, in the class-body const arm:

> *"Only the untyped forms below are scoped; typed (`const X: T = ..`) class
> consts have real storage and stay global (rare; tracked as a follow-up)."*

The untyped forms go through `ClassConstMangle(ci, name)` and land in the
`ClassConst*` registry keyed by owning class. The TYPED form skips both: it
keeps the bare name and gets ordinary global storage. So the registry lookup
`FindClassConst` cannot see it — which is the known "cannot qualify it"
symptom — and, because the name is bare and global, a second class using the
same const name silently overwrites the first.

"Rare" is what made this acceptable to defer. It is not rare in the code this
compiler is aiming at: `generics.helpers` publishes
`SIZED_SIGN_MASK: array[1..32] of UInt32` exactly this way, and a name like
`TAG` / `NAMES` / `DEFAULTS` on two classes in one unit is ordinary.

## What the fix has to do

Give the typed form the SAME treatment as the untyped one: register a
`ClassConst*` row (owner + visibility) and mangle the backing storage name, so

- two classes cannot share a slot,
- `FindClassConst` resolves it, which makes `TA.TAG[1]` work,
- and, once `feature-pascal-type-helpers`' type-name receiver is in,
  `UInt32.SIZED_SIGN_MASK[i]` follows for free — that path resolves the type
  name to the helper's ci and then uses this same registry.

`EmitClassConstNode` currently builds a literal node per kind (int/float/string/
set) from the mangled key. A typed const has real STORAGE rather than a literal
value, so it needs a storage-reference node, not a literal — that is the part
that is actual work rather than bookkeeping, and it is why the untyped forms
were done first.

Check the sibling before closing: class **VARIABLES** (`FindClassVar`) already
mangle, so they are fine, but verify a typed const inside a RECORD and inside a
type HELPER both land in the registry too — three declaration sites reach this
arm.

## Gate

`make compiler/pascal26` + the repro above + `tools/gate.sh quick`. The test
that bites is the two-class table, not the single-class qualified read: one
class alone works today, so a test with one class would pass before the fix.

---
track: P
prio: 65
type: bug
blocked-by: []
summary: "A TYPED class const (`const X: T = ...`) is registered under its BARE name in the global namespace, not under a class-mangled key like the untyped forms are. Two classes each declaring `const TAG: array[1..2] of Integer` therefore share one storage slot: TA.Get returns TB's value. Silent wrong value, no diagnostic; FPC gets it right."
status: done
owner: claude-acp
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

---

## Fixed — 2026-08-20

### What it was

The untyped class-const forms already got a `ClassConst` registry row and a
mangled backing name. The TYPED form (`const X: T = ...`) skipped both, on the
reasoning recorded beside it: *"typed class consts have real storage and stay
global (rare; tracked as a follow-up)"*. Because the backing name stayed BARE
and global, two owners declaring the same const name shared one slot.

Records were the same bug one level further out, and worse — their const
section was parsed with **no owner at all**, `ParseConstSection(-1, 0)`, with
the comment *"a constant has no storage and pxx does not scope declarations, so
there is nothing to scope."* Both halves of that are false for a typed const.

### The fix

1. **Declaration** (`ParseConstSection`, typed arm): register the registry row
   and mangle `name` **before** the storage is allocated, so `AllocVar` /
   `AllocArray` names the mangled key. Identical to what the untyped arm does.
2. **Records** now pass their own `ci` instead of `-1`. Visibility is passed as
   0 (public) deliberately: a record's sections are already restricted
   (protected/published are refused outright) and record consts were never
   visibility-checked, so this keeps today's behaviour rather than quietly
   tightening it.
3. **Lookup** — one new predicate, `FindClassConstSym`, placed beside
   `FindClassVar` because it answers the same question about the same kind of
   thing: the backing SYMBOL of a const that is storage rather than a literal.
   The three access paths (qualified `TFoo.X`, bare-in-method, const-folding)
   call it instead of each rebuilding mangle-then-`FindSym`. Where it hits, the
   caller re-enters `ParseLValueAST` on the symbol — exactly what a `class var`
   already does, which is what makes suffixes (`TAG[1]`, `.f`, `^`) parse.

The untyped forms are untouched: they have no symbol, `EmitClassConstNode`
still answers them as literals, and `FindClassConstSym` returns -1 for them.

### One real trap, worth recording

The first attempt at the bare-in-method path re-entered `ParseLValueAST`
**without consuming the identifier**. `ParseLValueAST`'s contract is that the
caller has already consumed the name — it reads the spelling from the token
INDEX it is handed, not from the cursor — and the literal path two lines above
does its own `Next` for exactly that reason. Symptom was
`Expected: ), but got: N` from an enclosing `Writeln('w: ', N)`, i.e. an error
about the CALLER's syntax with nothing wrong in the source. Capture the token
index, `Next`, then re-enter.

### Verified

`test/test_typed_class_const_scoping.pas` — two records and two classes, each
pair declaring the same typed const name, read bare (from a method) and
qualified, plus untyped consts in the same program to prove they were not
disturbed. Every row matches FPC 3.2.2 (`{$modeswitch advancedrecords}`).
The A/B pairing is the point: a single-owner test passes with or without the
fix.

### It closed type-helpers v3's last item for free

`UInt32.SIZED_SIGN_MASK[i]` — the open item in
[[feature-pascal-type-helpers]] — now works, along with the helper-name and
in-body spellings, because a helper IS a record and its consts now reach the
same registry the type-name receiver already used. No typed-const path was
added to the helper code. `test/test_type_helper_const_array.pas`.

## Log
- 2026-08-20 — resolved, commit ee388cf3a.

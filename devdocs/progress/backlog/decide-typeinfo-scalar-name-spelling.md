---
track: U
prio: 20
type: decide
blocked-by: []
summary: "TypeInfo(Integer)^.Name: pxx says `Integer`, FPC says `LongInt`. pxx's tyInteger and tyInt32 are separate type kinds where FPC's Integer IS LongInt, so TypeInfoOrdName picks one canonical spelling per pxx kind and Integer keeps its own. Cosmetic today (nothing branches on the string), but it is a visible FPC-parity gap in a compat-sensitive API, and changing it later breaks whatever started reading it."
status: backlog
owner: unassigned
---

# U TypeInfo name spelling for scalars: our canonical name, or FPC's?

- **Track U** (decision). Surfaced while widening `TypeInfo(T)`
  (`feature-typeinfo-all-types`); the code is landed and green either way, so
  nothing is blocked on this — it is a parity call worth making before a
  consumer depends on the string.

## The fork

`compiler/rtti_emit.inc`'s `TypeInfoOrdName` maps one canonical spelling per
pxx `TTypeKind`. Measured against FPC 3.2.2:

| source | FPC 3.2.2 | pxx today |
| --- | --- | --- |
| `TypeInfo(Integer)` | `LongInt` | `Integer` |
| `type TMyInt = Integer; TypeInfo(TMyInt)` | `LongInt` | `Integer` |
| `TypeInfo(Byte)` | `Byte` | `Byte` |
| `TypeInfo(Int64)` | `Int64` | `Int64` |

Only the `Integer` row differs, and it differs for a structural reason: in FPC
(objfpc mode) `Integer` is not a type of its own, it is an alias of `LongInt`,
so its typeinfo blob is LongInt's and carries LongInt's name. pxx has `tyInteger`
and `tyInt32` as **separate kinds**, so it has a name of its own to report.

## Options

1. **Keep `Integer`** (today). Honest about pxx's own type system; a user who
   writes `Integer` and reads back `Integer` is not surprised. Diverges from
   FPC on a string an FPC-targeting program could compare.
2. **Report `LongInt`** for `tyInteger`. Byte-for-byte FPC parity on the API.
   Costs: a pxx program that reads back the name it wrote gets a different
   word, and it entrenches an FPC implementation detail (that Integer is
   32-bit and spelled LongInt) into our RTTI.
3. **Make `Integer` a true alias of `tyInt32`** and delete the separate kind.
   The root-cause option — it removes the fork rather than choosing a side —
   but it is a type-system change with reach far past RTTI, so it is a
   different, much larger ticket, not a decision to take here.

## Recommendation

**Option 1, keep `Integer`** — unless a real corpus target is found comparing
the name against `'LongInt'`. Nothing in the repo branches on this string
today; the FPC-parity argument is real but hypothetical, and option 2 buys
parity on the one row by making the other rows describe FPC's type system
rather than ours. Revisit if a compat target actually reads it.

`test/test_typeinfo_named_types.pas` asserts the current answer explicitly and
points here, so whichever way this goes the test is the place to change it.

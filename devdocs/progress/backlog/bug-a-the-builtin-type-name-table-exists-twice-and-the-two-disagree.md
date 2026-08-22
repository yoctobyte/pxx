---
slug: bug-a-the-builtin-type-name-table-exists-twice-and-the-two-disagree
track: A
prio: 40
status: backlog
type: bug
summary: "`ByteBool(x)` and a dozen other builtin type names are rejected as `undefined variable` in a CAST while working fine in a DECLARATION — the two sites carry separate name->kind tables, and where they overlap they disagree."
---

# The builtin type-name table exists twice, and the two copies disagree

```pascal
var bb: ByteBool;          { fine — the declaration site knows the name }
begin
  bb := ByteBool(2);       { error: undefined variable (ByteBool) }
```

Same for `WordBool`, `LongBool`, `Int8`, `Int16`, `Int32`, `WideChar`,
`UCS4Char`, `Comp`, `ValReal`, `TDateTime`, `Currency`, `SizeInt`, `SizeUInt`,
`UTF8String`, `RawByteString`, `OleVariant`, `CodePointer` — every one of them a
legal cast in FPC.

## Two tables

- **Declaration**: `ParseTypeKind` (`compiler/pasparser_decl.inc` ~300-425), a
  ~40-arm `CaseEqual(lo, ...)` chain, each arm guarded `not tnHasAlias`.
- **Cast**: `compiler/pasparser_expr.inc` ~5624-5650, a second ~12-arm chain.

The cast chain is a subset — so a name added to the declaration chain (the
sized booleans were added for Synapse's bindings) does not become castable, and
nobody notices until someone writes the cast. There is precedent for the shared
form right there in the declaration chain: `BuiltinPtrNameElemTk(lo)` is already
a shared function for the P-names.

## Why this is not a five-minute fix — the tables DISAGREE

Where the two overlap they do not always answer the same thing:

| name | declaration | cast |
| --- | --- | --- |
| `longint` | `tyInt32` | `tyInteger` |
| `nativeint`, `ptrint` | `tyNativeInt` | `tyInt64` |
| `nativeuint`, `ptruint` | `tyNativeUInt` | `tyUInt64` |

So merging them is not a pure extraction: it changes what those four casts
produce. On x86-64 the widths coincide and the change is probably invisible;
`tyNativeInt` vs `tyInt64` is exactly the kind of distinction the 32-bit targets
and the RTTI/overload paths key off, which is why this wants the real gate and
a deliberate call on each disagreement, not a quick unify.

## Suggested shape

1. `BuiltinScalarTypeKind(const lo: AnsiString): TTypeKind` — the single table,
   returning `tyUnknown` for a non-builtin. Mirrors `BuiltinPtrNameElemTk`.
2. Declaration chain: replace the pure arms with one guarded call at the
   position of the current `real` arm. The removed names are disjoint from every
   remaining arm, so relative order among them cannot matter. Keep the arms with
   side effects (`shortstring` sets `LastTypeStrCap`, `pwidechar` sets
   `LastTypePointerElemTk`, `object`, the string family).
3. Cast site: call the same function. **Decide the four disagreements first**
   and record the decision in the commit.
4. Gate: this one earns `make test` + cross, not `--tier quick` — the
   disagreements are width- and target-sensitive.

## How it was found

The type-conversion/cast differential family (`ByteBool(2)`). Filed rather than
fixed because the microfix — adding three names to the cast chain — would make
the third copy of the divergence permanent while leaving every other missing
name broken. `devdocs/dev/root-cause-over-microfix.md`: bank the diagnosis, park
it, do not microfix as a consolation.

Failure mode is a loud compile error, not a wrong value, which is why the prio
is 40 rather than higher.

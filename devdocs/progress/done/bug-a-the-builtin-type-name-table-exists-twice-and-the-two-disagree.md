---
slug: bug-a-the-builtin-type-name-table-exists-twice-and-the-two-disagree
track: A
prio: 40
status: done
type: bug
summary: "`ByteBool(x)` and a dozen other builtin type names are rejected as `undefined variable` in a CAST while working fine in a DECLARATION — the two sites carry separate name->kind tables, and where they overlap they disagree."
owner: claude-A
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

## FIXED 2026-08-24 (claude-A)

Merged into one table, `BuiltinScalarTypeKind(const nm: AnsiString): TTypeKind`
in `compiler/pasparser_lval.inc`, placed beside `BuiltinPtrNameElemTk` — the
precedent the ticket named, and the position that matters: `pasparser_lval.inc`
is included before both `pasparser_expr.inc` and `pasparser_decl.inc`, so one
function is visible to both under the declaration-before-use rule self-host
enforces.

Twelve names became castable — ByteBool, WordBool, LongBool, Comp, ValReal,
TDateTime, Currency, SizeUInt, UTF8String, RawByteString, OleVariant,
CodePointer — and 35 duplicated arms left `ParseTypeKind`.

### The four disagreements, decided

The ticket said to settle these deliberately rather than let a merge pick.
**The declaration's answer won all four**, on one argument: a cast that
produces a different kind from the DECLARATION of the same name means one of
the two is wrong, and here it is always the cast.

| name | declaration | cast (was) | now | why |
| --- | --- | --- | --- | --- |
| `longint` | `tyInt32` | `tyInteger` | `tyInt32` | LongInt is 32-bit by definition. Both are 4-byte signed, so nothing observable moves; `tyInt32` merely stops claiming it is the target's *default* integer. |
| `nativeint`, `ptrint` | `tyNativeInt` | `tyInt64` | `tyNativeInt` | **Not cosmetic.** NativeInt is pointer-sized by definition, so `tyInt64` is simply false on i386, arm32, riscv32 and xtensa. |
| `nativeuint`, `ptruint` | `tyNativeUInt` | `tyUInt64` | `tyNativeUInt` | same |

Measured before and after, pinned vs HEAD, on x86-64 / i386 / arm32: the
`NativeInt(x)`/`PtrUInt(x)`/`LongInt(x)` **values are unchanged on every
target**. The old wrong kind was masked by the store — assigning to a 4-byte
variable truncates for free whatever the cast claimed. It surfaces where the
cast's TYPE is consumed instead of stored, and there the new answer is the
target-correct one: `SizeOf(NativeInt(x))` is now 4 on i386 and arm32 and 8 on
x86-64 and aarch64, matching `SizeOf` of a declared `NativeInt` on each.

### Shape

- The shared table holds **only side-effect-free names**. `shortstring`
  (sets `LastTypeStrCap`), `pwidechar` / `pchar` / `object` (set
  `LastTypePointerElemTk`), `textfile`, `file` and the promotable-int family
  keep their own arms at the declaration site, because they do more than name a
  kind. That line is stated in the function's header so the next person does
  not "finish" the merge by dragging them in.
- The declaration chain keeps its `not tnHasAlias` guard on the new arm, so a
  source or RTL declaration still wins — the property the P-name comment there
  calls load-bearing.
- `string` stays at the cast site: it is a keyword, not one of the
  identifier-spelled builtins.
- `UTF8String` / `RawByteString` are unconditionally `tyAnsiString`, kept as
  their own arm rather than folded into the `ansistring` one, which is
  conditional on `PXX_MANAGED_STRING`. They differ, and merging tables that
  differ is how this ticket started.

### Verified

`test/test_builtin_type_names_cast_and_declare.pas`, wired into `test-core`: 40
assertions — the twelve names that could not be cast at all, then every name
asserted as `SizeOf(cast) = SizeOf(declared var)`, then the widths the language
fixes. The pointer-sized rows are deliberately asserted as *agreement* rather
than against a literal, which is what makes the test mean anything on a 32-bit
target. `ALL OK` under fpc 3.2.2 and under pxx on x86-64, i386, aarch64 and
arm32.

A separate 20-row value differential against `fpc -Mobjfpc -O1` (`SizeOf` and
value of each cast of 258) is identical on 19 rows. The twentieth is
`ValReal`, where FPC's 10-byte x87 Extended meets our deliberate
Double (`feature-extended-alias-or-reject`); the test asserts the agreement
there and never a literal width, with the reason in place.

Self-host fixedpoint converged in one round; `tools/gate.sh quick` GREEN. (The
ticket's `Gate:` line asked for `make test` + cross. That line is superseded by
the per-fix loop — user, 2026-08-01, `decide-gate-line-convention` — so the
width- and target-sensitivity it was worried about was answered the way the
loop says to answer it: by running the differential on four targets here, and
leaving the matrix to Track T.)

### Found in passing, filed not folded in

[[bug-p-a-char-cast-does-not-truncate-to-one-byte]] — `Ord(Char(258))` is 258
where FPC gives 2. It was the one row of twenty still disagreeing after this
fix, it reproduces with the pinned binary, and it lives in a different file
(`ir.inc`'s narrowing mask explicitly excludes `tyChar` next to `tyBoolean`,
and only `tyBoolean` has a reason to be there). Folding an unrelated semantics
change into a table merge would make both harder to revert.

### Still separate, and now visible

`ConstIntCastWidth` (`pasparser_expr.inc` ~8951) is a THIRD copy of part of
this table — name to width-and-signedness, for const-expression casts. It was
not merged here: it answers a different question (bytes + signed, not a kind),
it is reached from the constant folder rather than the type system, and it
carries the same `longint`/`nativeint` disagreements this ticket just settled
in the other two. Three mechanisms for one concept is the design flaw
`devdocs/dev/root-cause-over-microfix.md` names; two is now the count. Filed as
[[refactor-a-the-const-cast-width-table-is-the-third-copy]].

## Gate

`make compiler/pascal26` converged + 40-assertion test on four targets + FPC +
the 20-row value differential + pinned-vs-HEAD value check on x86-64/i386/arm32
+ `tools/gate.sh quick` GREEN.

## Log
- 2026-08-24 — resolved, commit b1a007f27.

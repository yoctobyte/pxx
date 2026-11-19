---
slug: bug-a-fourteen-compiler-internal-record-names-are-reserved-in-every-user-program
track: A
prio: 45
type: bug
status: done
owner: claude-dupwt
created: 2026-09-06
found-by: frankD
blocked-by: []
summary: "IsRecordType (symtab.inc:2385) hard-codes FOURTEEN of the compiler's own descriptor record names -- TToken, TStrEntry, TFixup, TGlobFix, TCallFix, TSymbol, TParam, TProc, TRawToken, TTemplate, TSpecialization, TGenericFunc, TPendingGFSpec, TMethodFixup -- so that compiler.pas's own records carry known ids across the self-host. None of them is reserved in FPC and several are ordinary user type names (`TProc`, `TParam`, `TToken`). A user declaration of one of these wins ONLY if it lands in a table the shadow guard consults: aliases always did, ENUMS did not until 2026-09-06 (fixed; fcl-passrc's `TToken = (tkEOF, ...)` gave a tyRecord array ELEMENT beside a tyInteger VARIABLE, and pscanner refused three assignments with no position). A user RECORD or an OBJECT of one of these names still loses, silently, and the comparison is case-SENSITIVE (`lo = 'TToken'`) so one program can hold both readings: `array of TToken` took the builtin while `Array[ttoken] of String` took the enum. The list is a bootstrap mechanism wearing the shape of a type table; the fix is to scope it to the self-host rather than to add a fifteenth exception per table."
---

# The compiler reserves fourteen of its own record names in every program

```pascal
function IsRecordType(const lo: AnsiString): Integer;
begin
  Result := REC_NONE;
  if lo = 'TToken' then Result := REC_TTOKEN
  else if lo = 'TStrEntry' then Result := REC_TSTRENTRY
  ...
  else if lo = 'TMethodFixup' then Result := REC_TMETHODFIXUP;
```

Fourteen names, matched before any user table is consulted, in every
compilation. They exist for a real reason: `compiler.pas` declares these
records and the self-host needs them to carry stable ids. Nothing scopes them
to that program.

## What is already fixed, and what it cost to find

`pasparser_decl.inc` guarded the builtin with `FindTypeAlias(lo) < 0` — a user
`type X = ...` alias shadows it. An **enum is registered in the enum table and
is not an alias**, so `TToken = (tkEOF, tkWhitespace, ...)` — which is exactly
what `fcl-passrc/src/pscanner.pp:125` declares — lost.

The symptom was not a refusal at the declaration. It was:

```
pascal26:0: error: incompatible types: cannot assign Integer to record
pascal26:0: error: incompatible types: cannot assign record to Integer
pascal26:0: error: incompatible types: cannot assign Integer to record
```

`SortedTokens: array of TToken` recorded a **tyRecord** element while
`tk: TToken` stayed **tyInteger** — the same type name, two readings, eight
lines apart. Fixed 2026-09-06 by adding `FindEnumType(lo) < 0` to the guard and
clearing the stale `LastTypeRecId` on the fall-through.

**The row that did not complain is the one worth keeping.** pscanner's shell
sort has four assignments and only three are refused:

```pascal
tk := SortedTokens[J];            { mixed  -- refused }
SortedTokens[J] := SortedTokens[J+K];   { element to element -- SILENT }
SortedTokens[J+K] := tk;          { mixed  -- refused }
```

Both sides of the middle row are wrong the same way, so a check for agreement
agrees. **A same-shape move cannot see a systematic error in that shape**, and
it is the row a reader testing "does the swap work" writes first.

## The residual, which is why this ticket exists

1. **A user RECORD or OBJECT of one of these names still loses.** That case is
   indistinguishable from the self-host's own, which is what makes it hard: the
   guard cannot ask "is this the compiler compiling itself" from where it
   stands.
2. **Case sensitivity.** `lo = 'TToken'` is an exact match against a parameter
   whose name says lowercase. Every other type lookup here is
   case-insensitive (`FindEnumType` lowers). One program legitimately reaching
   two different types through two spellings of one name is the sharpest
   possible statement of the defect.
3. **The pattern generalises past this function.** Each table added its own
   exception as it was hit — alias, then enum. A third table will be found by
   the same route, which is the enumerated-predicate shape
   (`devdocs/dev/normalise-dont-special-case.md`).

## The fix worth doing

Scope the fourteen to the self-host rather than to the language: register them
as ordinary records of the unit that declares them (`defs.inc`) and let the
normal visibility rules answer, or gate the list on compiling `compiler.pas`.
That deletes the guard rather than growing it, and removes the question of
which user table gets an exception next.

Check while writing it: the self-host fixedpoint is the acceptance test and it
is cheap (`make compiler/pascal26`, ~12s), but it proves only that
`compiler.pas` still resolves. A program that declares `TProc` as a record and
one that declares it as a class both need a row.


# Fixed 2026-11-19 (claude-dupwt): the builtin id needs a declaration

Scoped to the self-host as this ticket asked, without a self-host flag:
compiler.pas DECLARES all fourteen records, so the self-host always reaches
IsRecordType's existing arm for a declared record of the builtin shape. The
only other way in was a name with NO visible declaration, which handed a user
program the compiler's record. That arm now answers REC_NONE, so the ordinary
unknown-type and forward-pointer paths answer.

Measured against fpc 3.2.2:

| program | before | now = fpc |
| --- | --- | --- |
| `PToken = ^TToken; TToken = record kind: Byte end` then `p^.kind` | `"kind": no such member` | `7 1 1` |
| `var t: TParam` with no TParam declared | compiles, SizeOf 40 | `unknown type: TParam` |
| `TProc = object a, b: Integer end` | `8 3` | `8 3` |

**The self-host is untouched, proven rather than assumed.** The old compiler
and the new one, compiling the same new compiler.pas, give byte-identical
output (cf7973899df2). Nothing in lib/ or compiler/builtin mentions any of the
fourteen names.

Tests: test_a_a_compiler_internal_record_name_is_an_ordinary_user_name (row
internalrecname26, fpc's output; the old compiler fails it at line 17) and
an inline `var t: TParam` refusal (internalrecname_u).

Not changed: the comparison is still case-sensitive (`lo = 'TToken'`). With
the declaration requirement that no longer matters for user code: a
differently-cased user declaration is just a user record.

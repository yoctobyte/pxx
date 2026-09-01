---
slug: bug-p-a-units-implementation-section-is-visible-to-its-importers
title: "A unit's implementation-section types, consts and routines are all visible to importers"
track: P
prio: 45
type: bug
status: backlog
found: 2026-09-02
found-by: frankB
owner: ""
blocked-by: []
summary: "pxx has no interface/implementation visibility boundary at all: a unit's implementation-section TYPES, CONSTS and ROUTINES are every one of them visible to any importer, where FPC rejects all four. Accepting what FPC rejects is normally not a defect, and the permissiveness alone is not what makes this worth fixing — the SHADOWING is. A leaked implementation name silently outranks a builtin of the same name for every importer, and that already shipped one wrong-value/memory-corruption bug: builtinheap's private `PWord = ^NativeInt` shadowed the builtin `PWord = ^UInt16` in every user program, so `PWord(p)^` read eight bytes instead of two and `PWord(p)^ := x` WROTE eight, silently, at every -O level. That instance is FIXED by renaming the RTL's alias to `PMachineWord`; this ticket is the residual mechanism, which will hand the same gun to the next RTL name that collides."
---

# A unit's implementation section is visible to its importers

## Repro — pxx accepts all four, FPC rejects all four

```pascal
unit secretu;
interface
procedure Pub;
implementation
type TSecretRec = record x: Integer; end;
const SECRET_K = 4242;
procedure Hidden; begin WriteLn('hidden called'); end;
procedure Pub; begin WriteLn('pub'); end;
end.
```

```pascal
program useit;
uses secretu;
var r: TSecretRec;
begin
  Pub;
  r.x := 7;
  WriteLn('leaked type TSecretRec: ', r.x);
  WriteLn('leaked const SECRET_K: ', SECRET_K);
  Hidden;
end.
```

pxx: compiles and prints `pub / leaked type TSecretRec: 7 / leaked const
SECRET_K: 4242 / hidden called`.

FPC 3.2.2: four errors — `Identifier not found "TSecretRec"`,
`Identifier not found "SECRET_K"`, `Identifier not found "Hidden"`,
`Error in type definition`.

So it is not one table with a hole. Types, consts and routines all leak, which
says the section boundary is not recorded ANYWHERE, not that one lookup forgot
to check it.

## Why this is not just harmless permissiveness

Per CLAUDE.md, us accepting what FPC rejects is not a defect, and on its own this
would be a `compat` note at best. The reason it is a bug is that
`FindTypeAlias` (compiler/symtab.inc:178) is consulted BEFORE the builtin-name
chain — deliberately, so a user's own declaration wins — and a leaked
implementation-section name is indistinguishable from a user's own declaration.
So a private RTL name silently re-types a builtin for code that never mentioned
that unit's internals.

That is not hypothetical. It shipped:

| | before | after |
| --- | --- | --- |
| `SizeOf(PWord(a)^)` | 8 | 2 |
| `PWord(a)^` inline | 1234605616436508552 | 30600 |
| `PWord(a)^ := 0` on `FF FF FF FF FF FF FF FF` | `00 00 00 00 00 00 00 00` | `00 00 FF FF FF FF FF FF` |

The write row is the dangerous one: six bytes of whatever followed, silently, at
every `-O` level, on x86-64. On i386 `^NativeInt` is four bytes, so it was two
bytes of overrun there rather than six.

## Why it survived this long

`PWord = ^NativeInt` is the ONLY leaked alias whose meaning DISAGREES with the
builtin of the same name. Censused every pointer alias declared in an
implementation section under `compiler/builtin/` and `lib/rtl/`: `PByte`,
`PInt64`, `PInt32`, `PDouble`, `PLongInt`, `PSingle`, `PVariant` all leak too,
and every one of them happens to MATCH the builtin meaning, so the leak is
invisible for them. One disagreeing name out of eight is exactly the
"80%-accurate name" case — the part you sample confirms it.

Note also that `builtin.pas:742` had already independently arrived at the right
answer and spells the type `PMachineWord`, with a comment explaining why. The
knowledge existed in the tree and did not propagate to its two siblings.

## The comments asserted the opposite, in the file, in writing

builtinwide.pas said the aliases "are not exported, and exporting them would put
PWord and PByte into every program that uses builtinheap, where a user's own
PWord would be silently re-typed (the trap CLAUDE.md names)". The belief was
exactly right about the consequence and exactly wrong about the premise — the
`implementation` keyword was doing nothing. Both comments now state the measured
behaviour instead.

## Shape of a fix

Record the section at declaration time and check it at lookup:

- a `DeclInImpl[]` flag parallel to `AliasUnitIdx[]` (and the routine/const
  equivalents), set while the parser is past `implementation`;
- `DeclVisible` (compiler/symtab.inc:52, body beside `VisibilityAllows`) returns
  False for an impl-section decl unless `declUnit = CurrentUnitIdx`.

`DeclVisible` is already the single choke point for the non-transitive `uses`
rule, so the type half is small. The routine and const tables need the same
flag; confirm they route through the same predicate before assuming one edit
covers all three.

**Expect fallout, and land it behind a flag.** A tree that has never had this
boundary will have code leaning on the leak — the four tests below did. Anything
that breaks is a real latent bug, but the volume is unknown and this is a
visibility change to a self-hosting compiler, so `make compiler/pascal26`'s
fixedpoint is the first thing to check, not the last.

## Already cleaned up (2026-09-02, so they will not confuse the fixer)

Four tests read a machine word through the leaked `PWord` and now declare their
own alias instead: `test_threadsafe_refcount_lockfree` (this one actually FAILED
on the rename — its `RC()` read the saturated sentinel `$40000000` through a
two-byte name and got 0), `test_pointer_cast_owned_string_refcount`,
`test_widestring_transcode`. `test_coswitch` and
`test_builtin_pointer_types_b303` already declared their own `PWord` at program
level and were never affected — the latter is precisely the test that asserts a
source declaration beats the builtin.

Regression coverage for the shadowing half is
`test/test_builtin_pword_not_shadowed_by_rtl`, wired into `test-core`, green on
x86-64/i386/aarch64/arm32/riscv32, positive control confirmed (15 failures with
the RTL alias restored, 0 after).

---
slug: bug-p-a-units-implementation-section-is-visible-to-its-importers
title: "A unit's implementation-section types, consts and routines are all visible to importers"
track: P
prio: 45
type: bug
status: done
found: 2026-09-02
found-by: frankB
owner: frankD
blocked-by: []
summary: "FIXED 2026-09-04. A unit's implementation-section types, consts, routines and vars are private to it, all four, checked per row in DeclVisibleSect from an InUnitImpl flag stamped at registration. AMBIENT units (builtin/builtinheap/pylib/pyeval/... -- compiler-injected, never named in a user uses clause) are exempt EXCEPT for the type-alias tables, which is where the shipped harm lived: FindTypeAlias runs ahead of the builtin name chain, so a leaked private alias can re-type a builtin. Measured before fixing with the new PXXDBG=p.implleak: 33 of 1741 sources broke, four causes; three were RTL entry points declared in the wrong section and one was a bug in the fix (C has no implementation section). Final 2571-source run: 309 fail vs the pin's 311, and the only source the pin compiles and this build refuses is the must-not-compile test added here."
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

## Resolution 2026-09-04 (frankD, Track P)

**The mechanism, as "Shape of a fix" proposed, plus one thing it did not
anticipate.** A `DeclInImplNow` stamp parallel to every `XUnitIdx[]` table
(alias, arraytype, enumtype, class, strconst, setconst, sym, proc), set from a
new `InUnitImpl` that `ParseUnit` owns and saves/restores around nested `uses`;
`DeclVisibleSect` is the single choke point and `DeclVisible` is now it with
`declInImpl = False`. The ticket asked whether "the routine and const tables
route through the same predicate": they do not — routines go through
`DeclVisibleBareRoutine`, which now carries the flag too.

**`InUnitImpl` is NOT the complement of the existing `InInterface`,** and
reaching for that instead is the trap. `InInterface` is also False for the main
program and for every compiler-injected registration that runs with
`CurrentUnitIdx` set to a unit name — the PXX* runtime stubs pre-register under
`builtinheap` in exactly that shape, and stamping those private makes every
program fail to find its own allocator.

### The measurement the ticket asked for, and the instrument it needed

`PXXDBG=p.implleak` reports each row the boundary would hide — kind, name,
declaring unit, use site — and lets it through. That is the difference between
one census pass and discovering the fallout one failing build at a time. It
costs nothing when off: every call site passes two integers, and the name is
materialised inside the report branch only.

Read it knowing it counts **rejected candidates, not breakages** — a name that
also resolves correctly elsewhere is reported and would not have broken. The
decisive number is the compile-failure delta, and the two differ by two orders
of magnitude (~200k report rows against 33 broken sources).

| arm | sources | fail |
| --- | --- | --- |
| boundary OFF (same binary, `PXXDBG=p.implleak`) | 1741 | 263 |
| boundary ON, before the RTL declarations | 1741 | 296 |
| boundary ON, after | 2571 (adds `.npy`) | 309 |
| pinned compiler, same list | 2571 | 311 |

The one source the pin compiles and this build refuses is
`test_unit_impl_section_is_private_fail.pas`, added here to be refused.

### What stopped compiling — four causes behind 33 sources

1. **builtinheap's and builtin's runtime entry points** — `PXXDivZero`,
   `PXXNilRef`, `PXXVariantError`, `PXXRangeChkI64`, the `PXXDyn*` family,
   `PXXArrayReleaseImmediate`, `PXXClassFinalize`, the seven `*Hook` variables,
   `__pxxTObjectEquals`/`GetHashCode`/`ToString`, `__pxxInheritsFrom`, and the
   rest. These are the units' ABI with the code generator and with sysutils,
   not private helpers: `textfile.pas` READS `PXXIoErrorHook` and `sysutils`
   WRITES it, both from outside builtinheap. `__pxxTObjectDestroy` and
   `PXXExitProcess` were already declared correctly in the interface; this is
   the rest of the family catching up. Safe to export from an ambient unit
   *because of the prefix* — `PXX`/`__pxx` is not a spelling user code writes,
   which is exactly why the pointer aliases beside them (`PByte`, `PInt32`, ...)
   stay private and each consumer declares its own.
2. **Four non-ambient library units.** `NextQueryId` and `ReadFileText`
   (dns_wire_blocking, dns — both called by dns_async, which `uses` them);
   `TypeKindSize`/`TypeKindSigned` (typinfo — whose own interface comment
   already pointed callers at them, i.e. documented a surface the unit did not
   export); `HttpRequestAsync` (http — called by its own `HttpGetAsync`
   wrappers and directly by a devtest). Every one is genuinely exported surface.
3. **`PAnsiString`** reached from `pyeval` into `builtin`'s implementation.
   Fixed the way the tree already fixes these: pyeval declares its own.
4. **A bug in this fix.** C has no interface/implementation section, so a
   `uses './x.c'` written inside a Pascal unit's implementation stamped every C
   symbol private and broke the flat cross-translation-unit linkage
   `VisibilityAllows` deliberately allows. Same for a `.py` module. Both
   branches of `CompileUnit` now clear `InUnitImpl`, as the Pascal branch does.

### Ambient units are exempt, except for the type tables — measured, not chosen for convenience

The quick tier's NilPy canary went red on `PyUnsupportedOperandError`. It is one
of **32** pylib names the compiler resolves by literal name, out of **188**
routines pylib declares in its implementation section, and `pyparser.inc` alone
holds **431** such lookup sites (`FindProc('...')`, `FindUClass('TPyList')`),
each reporting `Nil Python: pylib (...) not loaded` on a miss.

That is the code generator asking where its own helper lives, not user source
naming an identifier — and **no user clause ever names an ambient unit**
(`UnitIsAmbient`'s own comment: "injected by ParseProgram's epilogue, never
written by a user clause"). There is no `uses` for the boundary to be a rule
about, so enforcing it there buys a user nothing and turns every new RTL helper
into a confusing build break.

**The type-alias tables keep the rule even for ambient units, and that is the
half that makes this a bug rather than a compat note.** `FindTypeAlias` is
consulted before the builtin-name chain, deliberately, so a leaked private alias
is indistinguishable there from a user's own declaration — which is how
`PWord = ^NativeInt` came to outrank `^UInt16`. A class or routine name has no
builtin chain to outrank.

### Coverage, and one gap stated rather than papered over

`test/test_unit_impl_section_is_private.pas` (with `unit_impl_private.pas`) and
`test/test_unit_impl_section_is_private_fail.pas`, both wired into `test-core`.
Positive controls verified in both directions against the pin: the value half
reports `fail=3` under the pin and `fail=0` after; the negative half's four
diagnostics are **all four absent** under the pin and all four present after.
Both halves are needed — hiding the interface too would satisfy the negative
test, and the positive test cannot see a name that is merely unreachable. The
negative half asserts all four kinds rather than letting one stand in for the
rest, and references them independently (`SizeOf(TImplOnlyRec)`, not
`var r: TImplOnlyRec`) so a broken declaration does not turn three of the four
into cascades.

**Not covered by a test that can fail: the ambient-alias arm.** Every alias
still living in an ambient unit's implementation section (`PByte`, `PInt32`,
`PInt64`, `PDouble`, `PMachineWord`, `PU16`) agrees with its builtin
counterpart, so deleting that arm changes no observable value today. That is the
same shape as this ticket's own census finding — one disagreeing name out of
eight — and it is why the arm rests on the argument rather than on a green row.

### Not touched

`SpecUnitIdx` (the specialization table) carries no flag: a specialization row
is minted by the using scope rather than declared in a section, and generics are
frankB's slice. Alias and proc rows minted FROM a `uses` clause do carry the
stamp, so a template specialised at an implementation-section `uses` is private
to that unit — agreed with frankB as correct, and neither of us could construct
a case that wants otherwise.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 84ea8e470.

---
track: P
prio: 55
type: bug
blocked-by: []
status: done
owner: "frankS"
summary: "FIXED 2026-09-09 (this ticket's own fix, binary 0dfc79cd7408): pxx's `static` is now a DIRECTIVE flag of its own (UMthNoSelf / ProcNoSelf) instead of a synonym for `class method`, so a static method has no Self parameter, its two declaration parsers agree with the implementation parser, and its ADDRESS can be cast to a plain function pointer -- which is how rtl-generics dispatches every comparer. Three rows, one program, now byte-matching fpc 3.2.2: direct call 107/107, through `function(A: Pointer; ASize: SizeInt)` 107/107 (was 119), through a cast with an EXPLICIT leading Self 100/100 (was 107) -- that third row is the positive control and the two compilers were exactly INVERTED there before, which is what proved the routine was fine and only its arity was wrong. Fixture test_a_static_class_functions_address_has_no_hidden_self.pas covers a CLASS and a RECORD host (two different declaration parsers) plus a non-static `class function` as the negative control. gate.sh quick GREEN. DOES NOT UNBLOCK the rtl-generics rung on its own: `TComparer<LongInt>.Default` still answers nil, so at least one more wall sits behind this one and it is NOT this ABI -- do not read this resolution as the cure for that. The `direct` row was already correct before the fix and cannot fail, because a call the compiler emits passes the Self it also expects; only an ESCAPING address diverges, which is why nothing in the suite had caught it."
---

# A static class function's address carries a hidden Self

**Blocks [[feature-pascal-corpus-generics]]** — `uses Generics.Defaults` compiles
and runs since `163e146eb`, and `TComparer<LongInt>.Default` answers **nil**
where fpc answers a live comparer.

## The measurement — one program, three rows

```pascal
type
  TPlainFunc = function (A: Pointer; ASize: SizeInt): Pointer;
  TSelfFunc  = function (Self: Pointer; A: Pointer; ASize: SizeInt): Pointer;
  TSvc = class
    class function Pick(A: Pointer; ASize: SizeInt): Pointer; static;
  end;
class function TSvc.Pick(A: Pointer; ASize: SizeInt): Pointer;
begin Result := Pointer(PtrUInt(ASize) + 100); end;
const
  Table: array[0..0] of Pointer = (@TSvc.Pick);
```

| spelling | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `TSvc.Pick(nil, 7)` | 107 | 107 |
| `TPlainFunc(Table[0])(nil, 7)` | **119** | 107 |
| `TSelfFunc(Table[0])(nil, nil, 7)` | 107 | **100** |

The third row is the positive control and it is exactly inverted: the cast that
is WRONG under fpc is the one that works here. So this is not a corrupted
address or a bad relocation — the routine is fine and its ARITY is one greater
than the source says.

## Cause

`pasparser_proc.inc`'s Self block gives every method a Self at index 0, "including
a STATIC (class) method, whose Self is the CLASS". That is right for an ordinary
`class function`, whose Self IS the runtime metaclass and whose FPC idiom depends
on it. It is wrong for `static`, which in FPC means the method has no Self at all
and its body may not name one.

pxx does not distinguish them: `UMthIsStatic` is set from `isClassMethod`
(`pasparser_decl.inc:8671`) for a class and from `RecordMethodClassPrefix`
(`:5423`) for a record. **The `static` directive is parsed and does not reach the
signature.**

## Why nothing has caught it

Every ordinary call is emitted by the compiler, which passes the Self it also
expects — so the direct-call row above is correct, and a test that calls a static
method and reads its answer cannot fail. The divergence needs the ADDRESS to
escape into a plain function pointer, which is exactly what a dispatch table
does and what no small test does.

## What it will cost to fix

An ABI change for every `static` method: no Self parameter, no Self argument at
every call site, and the record/class-helper arms in both the decl and the impl
Self blocks re-checked against each other
(see devdocs/dev/debugging-playbook.md, "A RULE THAT LIVES ON ONE SIDE OF A
DECLARATION/IMPLEMENTATION PAIR FAILS BY AGREEING" — this pair has now produced
two bugs in one day). The narrow alternative — keep the hidden Self and strip it
only when a static method's address is TAKEN — is a thunk per method and does not
make `Self` unavailable inside a static body, which is the other half of what
`static` means.

Not attempted here: it is an ABI change and it wants its own seat.


## Resolution (2026-09-09, frankS)

`static` is now its own flag. `UMthIsStatic` keeps its meaning — "this is a class
method" — and an ordinary `class function` keeps its hidden metaclass Self, which
FPC's own idiom depends on. `UMthNoSelf` (per method) and `ProcNoSelf` (per proc
row) carry the directive.

**Read by LOOKAHEAD, in both declaration parsers**, because each writes param 0
before it reaches the directive run: `ParseRecordMethodDecl` writes `pn[0] :=
'Self'` immediately after the method name, and the class member loop registers
its proc row some seventy lines before the directive loop runs.
`StaticDirectiveAheadInMethodHeader` has two entry points for exactly that
reason. Learning about `static` afterwards would mean shifting ~30 per-param
columns back down and re-registering — the shape that has already produced two
bugs in this file by forgetting a column.

**The seven call sites are corrected in ONE place.** `GenMakeStaticMethodCall`
drops the Self argument when `ProcNoSelf[mpi]`, using the `lastArg = -1`
empty-chain convention `FillDefaultArgs` already speaks. Correcting each site by
hand is the same rule-per-caller shape that fails by an absent copy.

`FindUMethArity` and `FindUMethArityStrict` no longer add 1 unconditionally.
That matters and is not cosmetic: `TComparer<T>.Default` in rtl-generics is a
two-way overload of static class functions, and the unconditional `+1` drops both
candidates to the name-match fallback.

### What this did NOT fix

`uses Generics.Defaults` compiled and ran before this change and still does.
`TComparer<LongInt>.Default` answered nil before and **still answers nil**. The
next wall is somewhere in `_LookupVtableInfoEx` -> `TComparerService.LookupComparer`
-> `ComparerInstances[ATypeInfo.Kind]`, which is a `array[TTypeKind] of TInstance`
typed const plus `TypeInfo(T)` RTTI — not this ABI. Named here so nobody reads
this resolution as the rung's cure.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit b0d53c73a.

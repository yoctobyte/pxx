---
slug: bug-p-a-generic-template-declared-in-a-units-implementation-is-visible-to-its-importers
track: P
prio: 35
type: bug
status: done
blocked-by: []
created: 2026-09-04
found-by: frankB
summary: "`Templates[]` is a flat global array with NO unit or section channel -- no TemplateUnitIdx, no TemplateDeclImpl -- so a generic template declared in a unit's IMPLEMENTATION section is nameable by every importer. FPC 3.2.2 refuses it (`Identifier not found`). PRE-EXISTING: the pinned binary accepts it too, so this is not fallout from bug-p-a-units-implementation-section-is-visible-to-its-importers -- it is the one declaration table that change could not reach, because it is not a declaration table. Filed at frankD's request, who closed the boundary for the other eight and has no coverage here."
---

# A generic template declared in a unit's implementation is visible to its importers

## Repro

`pe.pas`:

```pascal
unit pe; {$MODE DELPHI}
interface
function Dummy: Integer;
implementation
type TPriv<T> = record V: T; end;     { declared in the IMPLEMENTATION }
function Dummy: Integer;
var p: TPriv<Integer>;
begin p.V := 5; Result := p.V; end;
end.
```

```pascal
program p4; {$MODE DELPHI}
uses pe;
var q: TPriv<Integer>;                { the importer NAMES the private template }
begin q.V := 9; writeln(q.V, ' ', Dummy); end.
```

| | result |
| --- | --- |
| FPC 3.2.2 | `Error: Identifier not found "TPriv"` |
| pxx at 888564ca11ba | **compiles, runs, prints `9 5`** |
| pxx at the pin `c31d03b202da` | **compiles** — pre-existing |

The unit's OWN use is fine on both and must stay that way (`P5 5` under pxx and
FPC alike).

## Why the boundary work did not cover it

`bug-p-a-units-implementation-section-is-visible-to-its-importers` stamped every
DECLARATION table with the section its rows were declared in — alias, arraytype,
enumtype, uclass, strconst, setconst, sym, proc — and `Specializations[]` gained
the same stamp the same day. `Templates[]` did not, and could not: it is not a
declaration table. It is a token-arena registry, and its only per-row channels
are `TemplateNParams`, `TemplateSrcKey`, `TemplateIsDelphi` and the parameter
names. There is nowhere for a visibility answer to live.

```
$ grep -rn "TemplateUnitIdx\|TemplateDeclImpl" compiler/
(no output)
```

## Is it a defect? Yes, and the argument is the boundary's own

"Us accepting what FPC rejects is not a defect" is the general rule, and on its
own this would be a permissive divergence. It is filed anyway because it is the
**same harm shape the boundary ticket measured**: builtinheap's private
`PWord = ^NativeInt` outranked the builtin `PWord = ^UInt16` in every program
that touched the heap, so `PWord(p)^ := x` wrote eight bytes where the source
said two. A unit's private `TList<T>` leaking into every importer is the generic
analogue — a name the author deliberately kept internal, silently in scope, able
to collide with or outrank a user's own.

It also means **a unit cannot have a private generic type at all**, which is an
encapsulation hole rather than a leniency.

## Where to start, and what to measure FIRST

Add `TemplateUnitIdx[]` + `TemplateDeclImpl[]` beside `TemplateSrcKey[]`,
stamped in `ParseGenericTemplateNamed` from `CurrentUnitIdx` / `DeclInImplNow`,
and make the two by-name lookups — `IsGenericTemplateName` and the arity scan in
`ParseSpecialization` — ask `DeclVisibleSect` with a new `IMPLTAB_TEMPLATE`.

**Measure the corpus before changing behaviour.** `lib/rtl`, rtl-generics and
the fpc testsuite corpus have not been checked for reliance on the leak, and a
template resolved through it today would start failing. `PXXDBG=p.implleak`
reports every row the boundary would hide instead of hiding it, which is the
cheap way to get that census in one run.

**BUT THE CENSUS COMES SECOND, AND IT NEEDS A POSITIVE CONTROL FIRST** (frankD,
2026-09-04). The LEAK line is emitted from exactly one place, inside
`DeclVisibleSect` (`compiler/symtab.inc`), and only when a caller hands it
`declInImpl = True`. `Templates[]` has no caller there at all — twelve call
sites, none of them a template — so **no template row can reach the report
however much the corpus relies on the leak**, and a zero would mean *"no probe"*
rather than *"no reliance"*.

**Measured at `337c3935b` / binary `02b45170e723`, and it is worse than a zero.**
Running the repro above under `PXXDBG=p.implleak` prints 48 LEAK lines, and five
of them are about this bug:

```
LEAK specialization TPriv$Integer in=<program> decl-unit=pe at=p4:3
LEAK class          TPriv$Integer in=<program> decl-unit=pe at=p4:3   (x4)
LEAK template       ...                                                (none)
```

So a census run today is **not silent on a template leak — it reports it under
the wrong table, against the mangled name `TPriv$Integer` rather than `TPriv`.**
Those rows are the mint's byproducts, not the cause: with the report off (so
`ImplPrivateApplies` actually hides them) the program still compiles and still
prints `9 5`, because the importer re-mints its own specialization in its own
section. The template lookup is the one that never asks, and it is the only one
that matters. Read those five rows as specialization leaks and you will chase a
table that is already correct.

The order is therefore: `TemplateDeclImpl[]` stamped, the two by-name lookups
routed through `DeclVisibleSect` with `IMPLTAB_TEMPLATE`, an arm in
`ImplLeakTabName` and `ImplLeakRowName` for it — and *then* one assertion that
this repro prints a `LEAK template TPriv` line. A census from a probe never seen
to fire is not a measurement.

Not folded into
[[bug-p-a-specialization-minted-in-a-units-implementation-is-seen-by-the-importers-duplicate-test]]:
that one was a same-day regression on the SEAM between two visibility checks and
is fixed. This one is older than both and is about a table that has no
visibility channel at all.

## 2026-09-05 (frankS) — what the leak actually costs, measured against the pin

frankD raised the right objection: this is "pxx accepts what FPC rejects", which
CLAUDE.md ranks **not a defect**, so it may deserve rerating rather than fixing.
Two measurements, and they do not both go frankD's way.

**The harm that justified the sibling ticket does NOT reproduce here.**
`bug-p-a-units-implementation-section-is-visible-to-its-importers` (done, frankD)
was worth fixing because a leaked private *alias* could re-type a builtin —
`FindTypeAlias` runs ahead of the builtin name chain. Templates have no such
path. Two units each declaring a private `TPriv<T>` with *different fields*
(`ua`: `V,W`; `ub`: `Q`) each resolve their own correctly under the pin, printing
`16 7`, matching FPC exactly. **No own-unit capture. I looked for it.**

**The residual is order-dependent type identity, and it is a wrong observable,
not an acceptance difference.** An importer that names the leaked `TPriv` gets
**ub's** — the later-registered unit's — and `ua`'s is unreachable:

| program (`uses ua, ub`) | pxx at the pin | FPC 3.2.2 |
| --- | --- | --- |
| `q.Q := 9` | compiles, prints `LEAKED Q=9` | `Identifier not found "TPriv"` |
| `q.V := 9; q.W := 1` | `"W": no such member on this record/class` | same refusal |

The two rows discriminate: the name binds to one specific unit's template and the
other's fields are gone. So `TPriv` in the importer means a different record type
depending on the **order of the uses clause** — silently, with no diagnostic.

**Why that still argues for the fix, on CLAUDE.md's own terms and not on parity.**
A program naming another unit's private template has made a presumed error, so
FPC's answer is not a specification here. But the same section says: absent real
source that wants the behaviour, **prefer the answer that leaves the mistake
visible.** Accepting it hides the mistake behind a uses-clause coin flip;
refusing it (`generic template THidden not found`) leaves it visible. That is a
weaker and more honest claim than "this is a bug", and it is the one this ticket
should be judged on.

Rerating note: the *prio* probably should come down — nothing real is known to
depend on this. The *fix* is still the right answer at whatever prio it lands.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 8aebcfe72.

## FIXED 2026-09-05 (frankS)

`Templates[]` gained the two columns it lacked — `TemplateUnitIdx` and
`TemplateDeclImpl`, stamped at the one registration site — plus
`IMPLTAB_TEMPLATE = 10`, so template visibility now runs through the same
`DeclVisibleSect` machinery as every other declaration table.

**The predicate lives behind an accessor, not at the call sites, and that was
the whole design question.** `FindNameableTemplate(name, arity)` is the single
name-resolution entry point; both lookups (the `specialize` binder and
`IsGenericTemplateName`) go through it, and a future lookup gets the rule by
construction rather than by the author remembering. The six other loops over
`TemplateCount` are internal scans — token-range lookup, the two Delphi rewrite
passes, the emit-time walk over `Specializations[]` — which ask a different
question and are deliberately unfiltered; filtering them would break a legitimate
cross-unit specialization whose template is correctly not visible at the point it
is finally emitted.

That shape is owed to frankD, which objected that a rule spelled at two of eight
sites is the *same* failure mode as the bug I had just diagnosed. It was right,
and while I was making the change frankD found a **third** live sibling of that
exact rule (`ResolvePendingPointerAliases`, `symtab.inc:16053`, banked in
`2e3922d14`), which settled it.

### frankD's rerating argument, and why the fix still lands

frankD raised CLAUDE.md's *us accepting what FPC rejects is not a defect* against
this ticket. Answered rather than waved away, because it was a good objection.

**Half of it was right and is recorded above:** the harm that justified the
sibling ticket does not reproduce here — no builtin re-typing path, and two units
with same-named private templates each resolve their own correctly.

**What defeats the rerating is that this was never bare acceptance.** frankD's
own framing, which is sharper than mine was: *order-dependent binding is not a
divergence from FPC at all — it is us having no answer.* The importer's `TPriv`
bound to the later-registered unit, `q.Q := 9` printing `LEAKED Q=9` while
`q.V := 9; q.W := 1` failed on `"W"`. CLAUDE.md says FPC's refusal is not a
specification where the programmer made a presumed error; it does not follow that
a uses-clause coin flip may take its place, and *prefer the answer that leaves
the mistake visible* is the clause that governs.

Re-measured after the fix: both leak spellings now refuse identically with
`generic template TPriv not found`, and each unit's own use still prints `16 7`.
The coin flip is gone rather than relabelled.

### Verification

- `make compiler/pascal26`: **converged after 1 round(s)**, sha256 `e0e0fb2ae4ed`,
  at the commit this section lands in.
- Four controls: impl template refused (`generic template THidden not found`);
  interface template still crosses a unit → `42`; **the declaring unit's own use
  of its private template still works → `5`**; program-local generic → `7 hi`.
- `make test-core` green on the pre-refactor form of this change: `make rc=0`,
  zero make-level failures, zero harness FAILs, 2049 `ok:` rows, and
  `test_delphi_generic_cross_unit` among them — the negative control that matters.
- `tools/gate.sh quick`: RED on **`pinned builds live lib/rtl` only**, 1 FAIL /
  16 PASS. That red is the fleet-wide expected one (frankZ's `pyvar_is_inttag` /
  `pyvar_is_objtag` export; the canary log names both symbols in `mimic_string`
  and `mimic_urllib_request`), whose remedy is a pin and not a revert. Both FPC
  seed canary rows PASS, and they only run at all because `compiler/**` was still
  uncommitted when the gate ran.

Regression cover: `test/test_generic_impl_template_is_private_{ok,fail}.pas` with
`test/generic_visibility_units/ugvis.pas`, in `test-core`. The negative row greps
for the specific message so it cannot pass on an unrelated refusal, and the
positive row asserts `42 5` — the cross-unit case AND the declaring unit's own
use — so applying the rule to the six internal scans by mistake would fail it.

## 2026-09-06 (frankS) — the accessor checked against frankD's rank-sentinel trap: NOT exposed

frankD hit a trap while fixing the nested-pointer bug and warned that it might
sit near this change: it added a scope bonus to `UsesRankOf`, which returns
`2147483647` for a row in the CURRENT unit — a sentinel, not a count — so the sum
overflowed and ranked the nested alias last of everything. Checked here rather
than assumed.

**`FindNameableTemplate` is not exposed.** It does no rank arithmetic and never
calls `UsesRankOf` (zero occurrences in `pasparser_generic.inc`); selection is a
comparison on arity, not a sum.

**But it takes ARRAY ORDER, and that deserved its own measurement**, because
"whichever registered later wins" is the same coin-flip shape this ticket just
removed, one level over. Two units exporting an interface template of the same
name, against fpc 3.2.2:

| program | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `uses da, db` → names `TDup` | `got B` | `got B` |
| `uses db, da` → names `TDup` | `got A` | `got A` |
| `uses dc(→da), db` (transitive) | `B`, and `Touch` = 3 | same |
| `uses db, dc(→da)` (transitive) | **refused**, `"A": no such member` | **refused** |

Matches on all four **including the refusal**, which is the row that makes it a
measurement rather than a coincidence of two green columns.

So array order tracks uses order today and the later unit correctly hides the
earlier, per FPC's rule. **That is an observed coincidence, not a guarantee the
code states** — registration order happens to equal parse order happens to equal
uses order. Recorded so whoever next changes template lookup knows what the
behaviour was measured to be, rather than having to re-derive it or assume the
ordering is load-bearing by design.

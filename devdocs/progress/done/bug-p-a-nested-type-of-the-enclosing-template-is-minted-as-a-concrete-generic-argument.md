---
slug: bug-p-a-nested-type-of-the-enclosing-template-is-minted-as-a-concrete-generic-argument
track: P
prio: 65
type: bug
status: done
blocked-by: [bug-p-a-qualified-type-name-cannot-be-a-generic-argument]
summary: "`TEnum<TPair>` where TPair is a type nested INSIDE the enclosing template is minted eagerly as `TEnum$TPair`, giving `unknown type: TPair` at TEnum's own line. Same shape as bug-p-a-generic-argument-that-is-another-templates-parameter-is-minted-as-a-concrete-type, which is fixed — that one catches PARAMETER names via a token-level scan, and a nested type name is not a parameter, so it slips through. 23-line repro, FPC prints 4. This is the current stop for `uses Generics.Collections` (generics.collections.pas:120, TEnumerator<TDictionaryPair>). Two mechanisms for one concept: read the whitelist analysis below before adding a third."
owner: unassigned
---

# A nested type of the enclosing template is minted as a concrete generic argument

Successor to
[[bug-p-a-generic-argument-that-is-another-templates-parameter-is-minted-as-a-concrete-type]],
found by that fix moving the corpus wall onto it.

## Repro — 23 lines, FPC prints `4`

```pascal
program n1;
{$MODE DELPHI}
type
  TEnum<T> = class
    Cur: T;
  end;

  TDict<TKey, TValue> = class
  type
    TPair = record
      K: TKey;
      V: TValue;
    end;
  var
    E: TEnum<TPair>;
    N: Integer;
  end;

var d: TDict<Integer, LongInt>;
begin
  d := TDict<Integer, LongInt>.Create;
  d.N := 4;
  WriteLn(d.N);
end.
```

```
pascal26:5: error: unknown type: TPair
  near: TPair   class Cur  >>> TPair  end
```

Line 5 is `Cur: T;` — inside **TEnum**, which is correct source. The error comes
from the streamed body of `TEnum$TPair`, a class that should never have been
minted.

## Why the previous fix does not cover it

`TPair` is not a template PARAMETER, so
`CollectTemplateParamNamesFromTokens` — which scans `Tokens[]` for
`Name < ... > =` headers and collects the names inside the group — does not see
it. It is a type that only exists once TDict is specialized, exactly like `TKey`,
but it is spelled as a nested declaration rather than as a parameter.

## The general rule, and what blocks it — read this before writing a third check

**This is now two mechanisms serving one concept**, which is the smell
`devdocs/dev/root-cause-over-microfix.md` names, and a third one would be a
design flaw rather than a fix. The concept both cases are groping at is:

> an argument may be resolved eagerly into an alias only if it names something
> **concrete at sweep time** — a builtin, or a type already declared at the top
> level. Anything else belongs on the deferred / nested-prerequisite path.

That is a **whitelist**, and it subsumes both the parameter-name case and this
one. It was not taken first because of an ordering obstacle that has to be
solved with it, not around it:

```pascal
type
  TBox<T> = class ... end;
  TRec = record ... end;      { declared AFTER the template }
var b: TBox<TRec>;
```

The sweep for TBox runs the moment TBox is declared, so `TRec` does not resolve
yet and a whitelist would defer it — and **nothing re-triggers the sweep**,
because the fixed point only re-runs when another TEMPLATE is declared. That is
a regression on ordinary working code, so the whitelist needs a re-sweep at some
later safe point.

**There is now a precedent for exactly that.** `DesugarImportedDelphiGenericUses`
(added in the cross-unit fix) re-runs the sweep at the end of a `uses` clause,
anchored so every edit lands above the live cursor. The end of a **type section**
is the analogous point for this case and looks like the natural home. Not
measured.

## Corpus

Current stop for `uses Generics.Collections`:

```
generics.collections.pas:120: unknown type: TDictionaryPair
  near: class abstract protected function DoGetCurrent >>> TDictionaryPair virtual
generics.collections.pas:123: unknown type: TDictionaryPair
generics.collections.pas:120: unknown type: PT
```

`TDictionaryPair` and `PT` are nested declarations of `TDictionary<TKey,
TValue>`, used as arguments to `TEnumerator<T>`. Note the wall is now **inside
the file the user asked to compile** — before the parameter-name fix it was
`generics.defaults.pas:46`, a file that contains no specialization at all.

## 2026-08-29 (frankP) — HALF DONE and PARKED, with the second half measured

**Landed:** the collector no longer harvests only parameter names. It is now
`CollectSpecializationBoundNamesFromTokens` — *every name whose meaning depends
on a specialization* — and it harvests both a template's parameters and the type
names its BODY declares, from the same token walk. `--debug` on the repro now
shows `paramform=TRUE` where it showed `FALSE`: the group is deferred to the
nested-prerequisite path instead of being minted. No regressions (16 named
generic tests, 8 `.expected` clean, `spec_per_unit` 4/4, both cross-unit tests,
self-host fixedpoint `a8f567c2455d`).

That is deliberately ONE procedure and not a second mechanism — see the smell
note above, which is why the parameter version was renamed rather than
duplicated.

**Still failing, and the trace says exactly where.** The deferral is now correct
and the *prerequisite* is wrong:

```
DGEN match at 41 na=1 paramform=TRUE          <- fixed: no longer minted eagerly
SPEC TDict$Integer$LongInt = TDict nested=1   <- the prerequisite is discovered
SPEC TEnum$TPair = TEnum nested=0             <- ...and emitted with TPair RAW
```

`TEnum$TPair = specialize TEnum<TPair>` is emitted at the TOP LEVEL, where
`TPair` does not exist. It only exists inside `TDict$Integer$LongInt`. The
substitution set applied when a template is specialized covers its PARAMETERS
(`TKey` -> `Integer`) and not the type names its own body declares, so a nested
name used as a generic argument survives into a top-level declaration unmapped.

### READ THIS BEFORE CLAIMING IT: the `blocked-by` is lifted and the ticket is NOT ready

`bug-p-a-qualified-type-name-cannot-be-a-generic-argument` is **resolved**
(`3ee9a672f`), so the dependency edge below is clear and `progress.sh` will
compute this ticket as unblocked. **It is still RED.** Those are two different
claims and the ranker can only compute the first.

**The machinery exists; the wiring does not.** Verified by running the reduction
AFTER that fix landed: the prerequisite emitter still writes an un-substituted
nested name and the file still fails with `unknown type: TPair` / `unknown type:
PT` at line 35. Nothing about this ticket's symptom changed. What changed is that
the frontend can now *read* the form the fix will need to *emit* — a qualified
argument is normalised to a minted single identifier
(`QualArgAliasName` / `NoteQualArgNeed` / `EmitQualAliasDecl` in
`pasparser_generic.inc`) — so the route that was impossible is now merely unbuilt.

A lifted edge over hollow content is the same failure as a stale blocker, wearing
the opposite sign, and it is the one the board cannot represent. Hence this
paragraph rather than a frontmatter field.

### CORRECTION, same day, after probing: the remainder is NOT one mapping

The paragraph below said "one mapping is missing, not the machinery". Measured,
that is **wrong** — or at best true only of the route it assumed. The correct
emission is the QUALIFIED form
`TEnum$... = specialize TEnum<TDict$Integer$LongInt.TPair>`, and pxx **cannot
parse a qualified type name in an argument position at all**:

```
TE = specialize TEnum<TOuter.TPair>;
  -> Expected: >, but got: .          (FPC compiles this and prints 5)
```

Filed as `bug-p-a-qualified-type-name-cannot-be-a-generic-argument` and now this
ticket's `blocked-by`. A generic argument is modelled as exactly ONE TOKEN
across five tests and one storage type (`NSpecArg: array of TRawToken`), so the
qualified route needs that widened first.

The other route — hoisting a specialization's nested types to their own
top-level `$`-aliases — is still open and avoids qualified names entirely.
**Neither route has been measured.** Choose deliberately and write the choice
here; do not discover it halfway.

**A probe that bounds the remaining work:** a nested type of a specialization is
already materialised correctly and usable — `TDict<Integer, LongInt>` with
`P: TPair` and `d.P.K := 3` compiles and prints `3`, matching FPC. So nothing is
missing from the nested-type machinery itself. What is missing is one mapping:
when the prerequisite is emitted, a nested name must be rewritten to whatever
that name is called inside the specialization being emitted for.

**Reduction is in `test/test_generic_nested_type_as_argument.pas`** (5 rows,
oracle FPC's) and is **deliberately NOT wired into the Makefile** — it is red,
and a red rule in `test-core` is a landmine. Wire it when the second half lands.

Its last two rows are the boundary in the other direction and were both live
hazards while writing the collector, not decoration: a genuinely concrete
argument must STILL be minted, and a method's DEFAULT PARAMETER VALUE must not
register its type as a nested declaration — `procedure P(a: Integer = 0)` is an
`Ident =` inside a class body, and reading it as one deferred every
`TBox<Integer>` in the file until the `type`-section state was added.

**Corpus is unmoved** by this half: `uses Generics.Collections` still stops at
`generics.collections.pas:120`.

## 2026-08-30 — RESOLVED via route B (hoist). Reduction 5/5 against FPC, and wired.

Both halves are now closed. The first (2026-08-29) stopped the eager mint; this
one supplies the emission.

**What was built.** `SpecializeStream` was split into a substitution half
(`SpecializeToBuffer`, ending at a filled buffer and touching `Tokens[]` not at
all) and the splice — a behaviour-preserving split, because the buffer was always
there and only the splice was welded to it. On top of that:
`CollectHoistCandidates` finds a template's own nested type declarations and
their RHS extents; `NestedSpecArg` gains a second mapping so an argument naming
one becomes the top-level name it is lifted to; `EmitHoistedDecls` writes
`specName$Nested = <RHS, substituted>;` into the prerequisite stream; and
`SpecializeToBuffer` collapses the in-body declaration's RHS to that name, making
it an **alias**.

**Two defects found by reading, neither of which had a test that would have
failed. Both are in the write-up because the next person will re-derive them
otherwise.**

1. **It would not have terminated, and the fix is a modelling change rather than
   a guard.** Emitting the hoists takes the DEFERRAL path, which re-emits the
   declaration behind them; the re-parse runs the candidate scan again, marks the
   same candidate used again, and defers again — redeclaring the hoisted type
   every round until the deferral counter calls it a cycle. The re-parse must
   still SEE the candidate as used, because the class body needs it to collapse
   the in-body RHS to an alias. So **"used" and "still to emit" are two
   questions**, and conflating them is what does not terminate.
2. **`HoistStart`/`HoistEnd` are absolute arena indices belonging to ONE
   template**, and `SpecializeToBuffer` has other callers (generic functions, the
   pending-method flush) whose ranges live in the same arena. A stale candidate
   set could collide with an unrelated range at the same index, so the gate is
   opened around the class-body stream only, not left on.

**Corpus: NOT advanced, and the figure in this ticket's summary is stale.**
Measured on this build and on `pinned`, same command
(`{$mode delphi}` + `uses Generics.Collections`, `-Fu<rtl-generics/src>`):

| binary | stop |
| --- | --- |
| `pinned` | `generics.collections.pas:146` — `generic templates must be class, record, interface, array or procedure declarations` |
| HEAD (this change) | **the same line, the same message** |

So the "current stop is line 120, `TEnumerator<TDictionaryPair>`" in the summary
above does not reproduce against either binary today, and this change moves the
corpus **not at all**. The next wall is
`TCustomPointersCollection<T, PT> = object` — a generic over an OBJECT type,
which the frontend rejects outright. That wall already had a ticket and a
DECISION — `bug-p-object-value-types-standard-meaning` [P p70, `working/`], from
`decided/decide-revisit-object-types-rtl-generics-fired-the-trigger`. I filed a
duplicate for it before reading `decided/`; mine is closed in `rejected/` with a
pointer. The one fact worth carrying across: the wall reproduces identically on
`pinned` and on HEAD, so it is long-standing and not a regression from this
session's generics work. Stated plainly because a
"this unblocks the corpus" claim is exactly the kind that gets believed and is
expensive to unwind.

**Do not read the `blocked-by` edge as "route A was unfinished".** It records
that `bug-p-a-qualified-type-name-cannot-be-a-generic-argument` gated this
ticket, and says nothing about whether that ticket's ANSWER is this ticket's
answer. It is not: route A is impossible (three declarations in a cycle, FPC
rejects the desugaring too — see the measurement above). The qualified fix made
the form readable; the form was the wrong one here.

**Test:** `test/test_generic_nested_type_as_argument.pas`, 5 rows, oracle FPC,
`total ok 5 / 5` on both, now **wired** into `test-core` and its
`test/UNWIRED.txt` exemption deleted, as that exemption instructed.

**Regression:** 25 named generic tests, 8 `.expected` clean, the rest identical to
`pinned`'s output; `test_generic_cycle_fail` still fails with its cycle
diagnostic (the control that a deferral change must not break). Self-host
fixedpoint `374fa81e8293`, converged after 2 rounds. `forwardlint` clean.

## Gate

The repro printing `4`; the two `test_generic_arg_is_enclosing_template_param*`
tests stay green; the existing generic tests stay green; the reduction lands in
`test/`; the per-fix loop.

## 2026-08-30 — RE-REDUCE. NO ERROR TEXT IN THIS TICKET IS CURRENT.

Recorded by the coordinator from two independent lane reports, because a caveat that
lives only in message traffic is not recorded at all.

**This ticket's repro has moved twice in one night, and the symptom count behind it is
lower than the ticket implies.**

| when | reported failure | moved by |
| --- | --- | --- |
| earlier | `unknown type: PT` (pxx-a5's reduction) | — |
| tonight | shifted off `PT` | frankA's bodyless fix `8e4d175d2` |
| tonight, later | `35: unknown type: TPair` | frankA's whitelist fix |

**And the symptom frankA chased tonight is NOT a fourth instance of this root bug.**
frankA states it plainly: after its fix, that ticket's own test passes while
`test_generic_nested_type_as_argument.pas` still fails — with a **different error at a
different line**. It was a separate regression frankA had introduced itself in
`8b85e4881` (an objfpc `generic TDict<...>` header failing a Delphi-shaped whitelist),
A/B'd across four binaries. Two different causes were wearing one error string.

**So whoever takes this: re-reduce from source. Do not bisect on any range this ticket
implies and do not grep for any error text it quotes** — including pxx-a5's `PT`, which
was correct when recorded. See face 178a in
[[feature-a-a-refusal-is-a-claim-with-a-date-on-it]]: an auto-filed or hand-filed
regression bounds when a symptom was **observed**, not when its cause landed, and a
recurring error string makes those look like one claim.

Nothing here impugns the original reduction. Error strings in this area are simply not
stable enough to serve as citations, which is a fact about the area and not about the
reporter.

## Log
- 2026-08-30 — resolved, commit 1be878631.

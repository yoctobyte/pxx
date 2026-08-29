---
slug: bug-p-a-generic-argument-that-is-another-templates-parameter-is-minted-as-a-concrete-type
track: P
prio: 65
type: bug
status: done
blocked-by: []
summary: "`TCmp<TKey>` written inside `TDict<TKey, TValue>`'s body is minted EAGERLY as the concrete alias `TCmp$TKey`, because DelphiRewriteGenericUses tests an argument only against the template it is currently rewriting (ti), and TKey belongs to the ENCLOSING template. The streamed class body then says `Val: TKey` and reports `unknown type: TKey` — pointing at the TEMPLATE's file, not the user's specialization. 15-line repro, FPC prints 5. Pre-existing on pinned. This is the ORIGINAL `unknown type: TKey` symptom of bug-p-a-delphi-mode-generic-from-a-used-unit-cannot-be-specialized, which turned out to be a second, independent defect."
owner: frankP
---

# A generic argument that is another template's parameter is minted as a concrete type

Separated out of
[[bug-p-a-delphi-mode-generic-from-a-used-unit-cannot-be-specialized]] on
2026-08-29. That ticket was originally filed as *"a generic type parameter is
unknown when a specialization is materialised cross-unit"* from the corpus error
`unknown type: TKey`, then renamed on the grounds that the `TKey` framing *"was
wrong"*. It was not wrong — it was **this**, a second defect that the
eleven-line repro walked past because a different one sat in front of it. Fixing
that one leaves this one exactly where it was.

## It is NOT Delphi-specific — measured 2026-08-29

Filed with a Delphi repro because the corpus is Delphi. The objfpc spelling of
the same program fails **identically**, and the `--debug` traces are the same
event for the same reason:

```
TEMPLATE TCmp startTok=10 endTok=17
DGEN match at 28 na=1 paramform=FALSE      <- the use inside TDict's body
SPEC TCmp$TKey = TCmp nested=0             <- minted before TDict exists
TEMPLATE TDict startTok=40 endTok=51       <- ...only now is TKey a parameter
```

`DelphiRewriteGenericUses` handles the Delphi surface as pattern A and the
inline `specialize` as pattern B **through one `isParamForm` test**, so both
surfaces mint the same wrong alias. Do not go looking for this in the Delphi
desugar alone.

## Repro — 15 lines, FPC prints `5`, pxx errors on `pinned` and on HEAD

```pascal
program w;
{$MODE DELPHI}
type
  TCmp<T> = class
    Val: T;
  end;
  TDict<TKey, TValue> = class
    C: TCmp<TKey>;
    K: TKey;
  end;
var d: TDict<Integer, LongInt>;
begin
  d := TDict<Integer, LongInt>.Create;
  d.K := 5;
  WriteLn(d.K);
end.
```

```
pascal26:5: error: unknown type: TKey
  near: TKey   class Val  >>> TKey  end
```

Line 5 is `Val: T;` — inside **TCmp's** declaration, which is correct source.
The error is reported from the streamed body of `TCmp$TKey`, a class that should
never have been minted.

## Cause

`DelphiRewriteGenericUses` (`pasparser_generic.inc`) decides whether a
`<...>` group can be resolved eagerly into an alias by asking whether any
argument is one of **ti's own** parameter names:

```pascal
for k := 0 to na - 1 do
  for kk := 0 to np - 1 do
    if ... TemplateParamNames[ti * MAX_TEMPLATE_PARAMS + kk] ... then
      isParamForm := True;
```

`TKey` is not one of `TCmp`'s parameters, so the group reads as concrete and is
minted. But it is not concrete: it stands for whatever the **enclosing**
template is specialized with, and belongs on the deferred / nested-prerequisite
path exactly like `TCmp<T>` inside TCmp's own body does.

## What does NOT fix it, measured

Widening that test to **any** template's parameter names was built, run, and
**backed out**: it changes nothing on this repro and nothing on
`generics.collections`. The reason is ordering — when TCmp's sweep runs, TDict
has not been parsed yet, so `TKey` is not any *known* template's parameter name.
The fixed point re-runs every template after TDict registers, but by then
`TCmp<TKey>` has already been rewritten to `TCmp$TKey` in round one. It also
costs nothing and buys nothing, so it is not worth carrying "just in case".

That rules out the cheap version. A real fix has to decide eligibility from
something that is true at round one — the obvious candidate being *"does this
argument name a type that resolves here?"*, which is a different question from
*"is it a parameter name"* and needs its own measurement, because a type
declared later in the same type section does not resolve at sweep time either.
**Direction, not diagnosis.**

## Corpus

This is the current stop for `uses Generics.Collections`:
`generics.collections.pas` writes `TComparer<TKey>` inside its dictionary
templates, and the error surfaces at `generics.defaults.pas:46` — a file the
user never wrote a specialization in, which is what made the original report so
hard to place. Byte-identical on `pinned`.

## Resolved 2026-08-29 (frankP) — read the parameter names out of Tokens[]

The enabling fact is wall 6's: **`LexAll` fills `Tokens[]` completely before the
parser starts**, so the enclosing template's header is already present as tokens
when TCmp's sweep runs. It is unparsed, not unavailable. So the eligibility test
stops asking `Templates[]` (which is parse-order dependent, and that dependence
IS the bug) and asks the token stream instead.

`CollectTemplateParamNamesFromTokens` scans for `Name < ... > =` and collects
the names inside the group. The `=` is the whole discriminator: a header is
followed by `=`, a USE is followed by `;`, `)`, `.` or a type opener, never by
`=` — and `a < b >= c` lexes `>=` as `tkGe`, so a comparison cannot spell the
shape. Constraints are skipped (`<T: TObject; U>` names T and U). Names are
collected speculatively per group and rolled back when the group turns out to be
a use. Run once per fixed-point round in both drivers.

**It is deliberately UNSCOPED** — every parameter name in the file, not just the
ones in scope at the use. That over-approximates toward *deferring to the nested
path*, which yields an honest error rather than a wrong class. That direction
matters: it is the opposite of the one wall 6's ticket warns about (*"do not
weaken the prerequisite scan… a wrong specialization is far harder to see than
an absent one"*). The cost is a real type sharing a name with somebody's type
parameter; the benefit is a test that does not depend on parse order.

**Not Delphi-specific, and the tests say so.** Both surfaces go through one
`isParamForm`, so there is an objfpc test as well as a Delphi one — reading the
`Delphi` in `DelphiRewriteGenericUses` and concluding objfpc is unaffected is the
mistake that test guards.

**What was tried first and backed out** (recorded in the section above): widening
the test to every *registered* template's parameter names. It fixes nothing,
because at TCmp's sweep the enclosing template is not registered yet. Same idea,
wrong source of truth — `Templates[]` instead of `Tokens[]`.

### This fix is a PARTIAL, by design, and the successor is filed

The concept underneath is *"an argument may be minted only if it is concrete at
sweep time"*, which is a **whitelist**. This is a blacklist of parameter names,
and it does not catch a **nested type** of the enclosing template —
`TEnum<TPair>` where `TPair` is declared inside `TDict<TKey, TValue>`. Filed as
[[bug-p-a-nested-type-of-the-enclosing-template-is-minted-as-a-concrete-generic-argument]]
with a 23-line repro, the whitelist analysis, and the ordering obstacle that
blocks it (a top-level type declared *after* the template would be deferred with
nothing to re-trigger the sweep — solvable the way the uses-clause hook solved
its version, at the end of a type section, unmeasured).

**Two mechanisms for one concept is the smell**, so it is named here rather than
left for someone to rediscover on the third one.

### Verification

- Both repro arms print `5`, matching FPC 3.2.2; both fail on `pinned`.
- New: `test/test_generic_arg_is_enclosing_template_param.pas` (5/5, and its
  fifth row is the other half of the boundary — a genuinely concrete argument
  must STILL be minted, so a fix that defers everything fails it) and
  `test/test_generic_arg_is_enclosing_template_param_objfpc.pas` (1/1). Oracles
  are FPC's. Both wired into `test-core`.
- 14 named generic tests, 8 `.expected` diffed clean,
  `test_generic_cycle_fail` and `test_default_unspecialized_generic_fail` still
  correctly refused (the latter with the byte-identical message `pinned` gives),
  `test_generic_spec_per_unit` 4/4, the cross-unit tests 4/4 and 1/1, the
  seven-program cross-unit repro set green.
- `generics.defaults.pas` still compiles alone, same code size (668510B).
- **Corpus moved**: `uses Generics.Collections` no longer stops at
  `generics.defaults.pas:46` — a file containing no specialization — but at
  `generics.collections.pas:120`, inside the file being compiled, on the nested
  type above.
- `make compiler/pascal26`: `converged after 1 round(s)`.

## Gate

The repro printing `5`; `generics.defaults.pas` keeps compiling alone; the
existing generic tests (19 named + 8 `.expected`) stay green; the reduction
lands in `test/`; the per-fix loop.

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.

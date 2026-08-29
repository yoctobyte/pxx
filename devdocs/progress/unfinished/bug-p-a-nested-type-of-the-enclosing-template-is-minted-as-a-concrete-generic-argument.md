---
slug: bug-p-a-nested-type-of-the-enclosing-template-is-minted-as-a-concrete-generic-argument
track: P
prio: 65
type: bug
status: unfinished
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

## Gate

The repro printing `4`; the two `test_generic_arg_is_enclosing_template_param*`
tests stay green; the existing generic tests stay green; the reduction lands in
`test/`; the per-fix loop.

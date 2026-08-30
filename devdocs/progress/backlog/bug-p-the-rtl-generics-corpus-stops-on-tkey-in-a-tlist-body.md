---
slug: bug-p-the-rtl-generics-corpus-stops-on-tkey-in-a-tlist-body
track: P
prio: 60
type: bug
status: backlog
blocked-by: []
summary: "DIAGNOSED 2026-08-30 — the title is wrong and the diagnostic was right all along. `IEqualityComparer<TKey>` (inc/generics.dictionariesh.inc:56) is a nested specialization of a generics.defaults.pas template using `TKey`, a parameter of the ENCLOSING template `TCustomDictionary<CUSTOM_DICTIONARY_CONSTRAINTS>` whose parameter list arrives from a `{$DEFINE}` macro. It is minted as a concrete specialization instead of being deferred, so `TKey` is passed as a real type and is not one. Nothing to do with TList, nothing to do with file attribution. Original framing: The rtl-generics corpus wall, as of binary d5a35c8de13a: `unknown type: TKey` raised while replaying a `TList<T>` method body, where `TKey` is not a parameter of `TList<T>` and the surrounding tokens still show `SizeOf(T)` with `T` un-substituted. Symptom recorded from a measurement; the mechanism is NOT diagnosed and the obvious story (a body replayed against another template's parameter set) is a hypothesis only. Unmoved by the cross-unit interface-splice fix — it fires before splice placement can matter, so it is the thing actually holding `uses Generics.Collections`."
owner: unassigned
---

# The rtl-generics corpus stops on `TKey` ~~inside a `TList<T>` body~~

> **Title is wrong — see the DIAGNOSED section at the bottom.** It is not `TList`,
> and there is no mis-attribution. Slug kept because other tickets cite it.

This is the current wall for the `Generics.Collections` corpus. Recorded as a
**symptom with a measurement**, deliberately without a root cause — see the
warning at the bottom.

## Measured

```
$ pascal26 -dVER3_0_0 -Fu<rtl-generics/src> gcprobe.pas     # binary d5a35c8de13a
pascal26:78: error: unknown type: TKey
  near: ) * SizeOf ( T ) >>> ) ; FillChar
pascal26:79: error: unknown type: TKey
  near: [ ANewIndex ] , SizeOf ( >>> T ) ,
```

~~`-dVER3_0_0` is required to get this far~~ — **NO LONGER TRUE, re-measured
2026-08-30 on binary `a9a4818ab6c8`.** Without the flag the corpus reaches the
*identical* wall, with zero `TArray` errors:

```
$ pascal26 -Fu<rtl-generics/src> gcprobe.pas        # no -dVER3_0_0
pascal26:78: error: unknown type: TKey
pascal26:79: error: unknown type: TKey
```

flagged by frankB and confirmed here rather than inherited. Two candidate
reasons, **not separated**: frankB landed `TArray<T>` in `lib/rtl/sysutils.pas`
on 2026-08-30, and `generics.collections.pas:57` declares its own `TArray<T>`.
Either way the flag is now a free variable — drop it when reducing.
[[bug-b-rtl-provides-no-tarray-generic-but-pxx-claims-ver3-2-2]] should be
re-checked against this before anyone works it. Runtime ~1m10s either way.

The reported file/line are not the real ones; the `near:` text places both
errors in `generics.collections.pas` (`:1631`/`:1635` and `:1687`), inside
`TList<T>` method bodies. That mis-attribution is its own ticket,
[[bug-p-a-specialized-body-reports-errors-in-the-wrong-file]] — chase it first
if you want the error to lead you to the right source.

## What is odd about it

Two observations from the same token run, which is why they are recorded
together and why neither is a conclusion:

1. **`TKey` is not a parameter of `TList<T>`.** It belongs to the
   `TDictionary<TKey, TValue>` family. A `TList<T>` body should have no way to
   name it.
2. **`T` came through un-substituted.** `SizeOf(T)` still reads `T` in the very
   tokens the error points at. Substitution either did not run over this range
   or ran with the wrong table.

## It did not move with EITHER generic fix

Two fixes have now landed without touching it:

Same probe, same flags, pre-fix `b3c6858bdfbb` and post-fix `d5a35c8de13a`:
byte-identical output. The cross-unit interface splice
([[bug-p-a-cross-unit-specialization-streams-method-bodies-into-the-interface]])
is a real fix with its own passing gates, but this failure fires before splice
placement can matter, so it — not that — is what holds the corpus.

And [[bug-p-a-specialized-body-reports-errors-in-the-wrong-file]] (fixed at
`a9a4818ab6c8`) does not move it either: the corpus still names
`generics.defaults.pas`, byte-identically, which is its own finding —
[[bug-p-the-corpus-instance-of-the-wrong-file-diagnostic-survives-the-fix]].
So the wrong `in:` you see when reducing this ticket is still wrong; do not
open the file it names.

## Do not write a cause into this ticket from the above

The tidy story is "a body is being replayed against another template's parameter
set". That is a **hypothesis built from two lines of `near:` text**, on a probe
whose position reporting is independently known to be broken. Reduce it to a
small standalone case first, and vary the shape — one template vs two in a unit,
`TList<T>` alone, a dictionary alone — before believing any of it. The repo's
history of wrong root causes is entirely made of plausible stories nobody
diffed against an oracle; `tools/fpc_diff_probe.sh` is the oracle here.

---

# DIAGNOSED — and both the title and the original framing are wrong

Keeping the original text above unedited; this section replaces its conclusions.

## The diagnostic was correct. All of it.

`PXXDBG=a.srcmap:*`, binary `a9a4818ab6c8`:

```
PXXDBG a.srcmap SPLICE start=42607 count=27 src=.../generics.defaults.pas resumes=3
PXXDBG a.srcmap tok=42616 srcline=78 -> .../generics.defaults.pas
pascal26:78: error: unknown type: TKey
  in: .../generics.defaults.pas
```

Token 42616 is inside `[42607, 42634)`, a body spliced from
`generics.defaults.pas`. **File right, line right.** `generics.defaults.pas:78`
is inside `IEqualityComparer<T>`, and the error is in its specialized body.

`TKey` occurs zero times in that file because it is the **substituted
argument**, not because the attribution is wrong. That grep — the one piece of
"coordinate-free" evidence two agents relied on — measured the expected state of
every specialization there has ever been.

## The actual mechanism

`inc/generics.dictionariesh.inc`:

```pascal
{$DEFINE CUSTOM_DICTIONARY_CONSTRAINTS := TKey, TValue, THashFactory}   { collections.pas:32 }

  TCustomDictionary<CUSTOM_DICTIONARY_CONSTRAINTS> = class abstract    { :47 }
  ...
    FEqualityComparer: IEqualityComparer<TKey>;                        { :56 }
```

`IEqualityComparer<TKey>` is a nested specialization whose argument is a
**parameter of the enclosing template**. That must be deferred, not minted as a
concrete alias — the case
[[bug-p-a-nested-type-of-the-enclosing-template-is-minted-as-a-concrete-generic-argument]]
exists for and `test_generic_arg_is_enclosing_template_param` covers. Here it is
minted, `TKey` is handed to `IEqualityComparer<T>`'s body as a real type, and it
is not one.

**The hypothesis for why the existing guard misses it — NOT confirmed:** the
enclosing template's parameter list arrives through a `{$DEFINE}` value macro,
so the "is this name one of my own parameters?" check may never see `TKey` as a
parameter. frankB ruled out the macro-as-declaration-parameter-list shape *on
its own*, with a control; it did not test that shape **combined with a nested
specialization on one of those parameters. That combination is the experiment.**

## Retitle

The title says `TList` and it is not `TList` — that came from the stale `near:`
window. Slug kept: it is an address and other tickets cite it.

## What the reduction should be

Three shapes, smallest first, each with a control:

1. enclosing template with a literal parameter list, nested specialization on a
   parameter — expected to WORK (this is the covered case);
2. enclosing template whose parameter list comes from a macro, **no** nested
   specialization — expected to WORK (frankB measured this);
3. **(1) and (2) together** — the corpus shape, expected to FAIL.

If 3 fails and 1 and 2 pass, the macro-defeats-the-parameter-check story is
established rather than assumed, and the fix belongs beside the existing guard.

---

## The macro hypothesis is FALSIFIED — eight controlled negatives, two agents

Every shape below **compiles and runs**, on binary `a9a4818ab6c8`. None
reproduces. Recorded so nobody re-runs them.

| # | shape | result |
| --- | --- | --- |
| 1 | literal parameter list + nested specialization on a parameter, inner template cross-unit | pass, prints 4 |
| 2 | macro parameter list, no nested specialization, params used in bodies | pass |
| 3 | macro parameter list **+** nested specialization on a macro-supplied parameter | **pass** |
| 4 | shape 3 + the INCLUDE BOUNDARY (macro defined in the unit, template declared in a `{$I}` file) | pass, procs 244→245 |
| 5 | shape 3 + `class abstract` + a nested `public type` block aliasing a two-parameter template on both enclosing params | pass, procs 245 |
| 6 | `uses Generics.Defaults;` alone | **compiles clean** |
| 7 | the corpus's own `TCustomDictionary<CUSTOM_DICTIONARY_CONSTRAINTS>` with `FEqualityComparer: IEqualityComparer<TKey>`, against the **real** Generics.Defaults | pass |
| 8 | the corpus's `TCustomArrayHelper<T>` with `TComparerBugHack = TComparer<T>` and `IComparer<T>` parameters, against the **real** Generics.Defaults | pass |

frankB independently ran shape 3 with an *interface* inner template and a
`class abstract` outer, instantiated it non-vacuously (procs 242→245), and got
the same negative.

**So: the `{$DEFINE}` macro parameter list does not defeat the
enclosing-parameter check.** Shapes 7 and 8 are the strongest of these — they are
the corpus's own declarations against the corpus's own `Generics.Defaults`, and
they compile. Whatever the trigger is, it is not in the declaration that
produces the error.

This is what filing the mechanism as a hypothesis rather than a cause bought:
the hypothesis was wrong, and nothing downstream had been built on it.

## One live lead, recorded as a lead

Removing **only** the implementation-section include from a corpus copy
(`{$I inc\generics.dictionaries.inc}` at `generics.collections.pas:2333`)
does not merely drop the `TKey` error — it produces a **different and earlier**
one:

```
pascal26:1313: error: unexpected token in a unit interface section:
  it starts no declaration (a mistyped section header?)
  near: Create ( AList : TCustomList < >>> T > )
```

An **interface**-section parse outcome that changes when an
**implementation**-section include is removed is not something a clean
declaration parser should produce. That is the same neighbourhood as
[[bug-p-a-cross-unit-specialization-streams-method-bodies-into-the-interface]]
(fixed `d1d8a0800`), which was about method bodies being streamed into an
interface section.

**Not diagnosed.** Two readings are open and this measurement does not separate
them: the `:1313` error may be newly *caused* by the removal, or it may have
been there all along and *masked* by the earlier failure — the
earlier-error-hides-a-later-one pattern that has already bitten this repo twice.
Establish which before building on it.

## Where the next person should start

Not more ingredient guessing — that avenue is exhausted above. Bisect the corpus
itself on a copy (`cp -r` the src tree; both includes are plain `{$I}` lines).
The two halves to separate first are whether the trigger is in the interface
half (through `:470`) or needs the implementation half (`:2333`), and the
`:1313` lead above is the first thread.

---

## NARROWED: collection is fine, CONSULTATION is where it breaks

Binary `54a79a8a5cf1`. Three measurements, in order, each killing a candidate:

**1. The spec-bound name table does not overflow.** `MAX_SPEC_BOUND_NAMES = 512`
(`pasparser_generic.inc:734`) and the cap is silent — past it a real type-parameter
name is simply not recorded, and the only symptom is exactly this wall. Its own
comment says the occupancy is reported *"so a near-miss is visible before it
becomes a wall"*, and it earned that:

```
PXXDBG p.specbound names=294 cap=512 overflow=0
```

294 of 512. Not the cause.

**2. `TKey` IS in the collected set** — 4800 hits, 45 distinct names including
`TKey`, `TValue`, `TDictionaryPair`, `PDictionaryPair`, `THashFactory`. So
`CollectSpecializationBoundNamesFromTokens` sees the macro-supplied parameter
list correctly; the `{$DEFINE}` does not hide the names from it. That is the last
version of the macro hypothesis, and it is dead too.

**3. Therefore the defect is in CONSULTATION, not collection.**
`pasparser_generic.inc:1169` is the loop that sets `isParamForm := True` when any
argument of a `<...>` group matches a spec-bound name. `TKey` is in the set and
`IEqualityComparer<TKey>` is still minted as a concrete alias, so either that use
never reaches this consultation site, or `isParamForm` is set and the deferred
path mints anyway. **That is the fork to resolve next, and it is two arms rather
than an open field.**

### The error set is wider than "TKey", which supports the same conclusion

On `6dfcd257a9f5` the wall reports `TKey`, `TValue`, **`TDictionaryPair`** and
**`PDictionaryPair`**. The last two are NESTED TYPES of the enclosing template,
not parameters — and `CollectSpecializationBoundNamesFromTokens` deliberately
collects both kinds as *"two kinds, one concept"*. The whole set leaks together,
which is what a single consultation failing looks like, and not what a
name-by-name collection gap would look like.

### Tooling: `p.specbound` now answers the other half of its question

`PXXDBG=p.specbound` printed only the OCCUPANCY. That answers "did the table
overflow" and cannot answer "is my name in it" — and a name never collected and a
name collected but never consulted produce the *identical* symptom. The count
cannot separate the two mechanisms, which is why this took three runs instead of
one.

Added `PXXDBG=p.specbound:names` (list them all) and `PXXDBG=p.specbound:<Name>`
(ask about one).

**A caution earned the hard way, in one shell line.** The first
`p.specbound:TKey` run came back with no hits and I nearly recorded "TKey is not
collected". It was a `sort -u | head -12` truncating the probe's own output — not a
compiler result. Re-running it cleanly gave 4800. That would have been the fourth
inverted reading of the day and the first from an instrument written twenty
minutes earlier. **Verify a new probe against a control before believing a null
from it.**

### Bisection is a dead end on this corpus — do not retry it

Two cuts were tried and both are invalid, for the same reason:

| cut | what happened |
| --- | --- |
| remove the implementation include only | the include holds method BODIES for classes declared in the header include, so removing it changes what `BufferGenericMethod` buffers — the machinery the failure runs through. **The experiment perturbs its own subject.** |
| remove BOTH includes (a whole-declaration cut) | `generics.collections.pas` references the dictionary family further down, so the unit no longer parses: a new error at `:1030` instead. |

`generics.collections.pas` is too densely interdependent to cut. The instrument
(`p.specbound`, `a.srcmap`, `p.dgen`) is the way in, not deletion.

---

## NARROWED AGAIN: the classification is CORRECT. The defect is downstream of it.

Binary `d5623b4d45d4`. Both arms of the previous fork are dead.

`PXXDBG=p.dgen:IEqualityComparer` on the corpus prints every sweep window and
every `<...>` group the rewrite considered for that template:

```
sweeps: 78     groups: 1838     groups with args=TKey: 674
paramform distribution over those 674:   674 x paramform=1     0 x paramform=0
```

- **Arm (a) — "the use never reaches the consultation site" — dead.** 674 groups
  with `TKey` as the argument are seen. The sweep is forward-only from
  `insertAt`, so a use earlier in the token stream than the sweep start would be
  invisible; that is not what happens here.
- **Arm (b) — "`isParamForm` is set and the deferred path mints anyway" — dead as
  stated.** `isParamForm` is set on **every single one**, 674 of 674, at exactly
  the corpus lines: `inc/generics.dictionariesh.inc:56`, `:82`, `:83`.

So `DelphiRewriteGenericUses` does the right thing. It sees the group, it
recognises `TKey` as a spec-bound name, and it sends the group down the deferred
path rather than minting a concrete alias.

**The bug is therefore in what the DEFERRED path does with a correctly-classified
group** — the nested-specialization / nested-prerequisite handling in
`ParseSpecialization`, not the decision that routed it there. That is a different
region of the file and a different set of code from everything examined so far.

### Running tally of eliminated mechanisms

| candidate | verdict | instrument |
| --- | --- | --- |
| the `{$DEFINE}` macro parameter list defeats the enclosing-parameter check | dead | 8 constructed shapes, 2 agents |
| `MAX_SPEC_BOUND_NAMES` overflow silently drops the name | dead | `p.specbound` — 294 of 512 |
| `TKey` is never collected as a spec-bound name | dead | `p.specbound:TKey` — 4800 hits |
| the use is outside the rewrite's forward sweep window | dead | `p.dgen:IEqualityComparer` — 674 groups seen |
| the group is misclassified as concrete | dead | same — 674/674 `paramform=1` |
| **the deferred path mishandles a correctly-classified group** | **open** | — |

Five mechanisms eliminated by measurement rather than by argument, and the sixth
is where to start. Note that the first three were each the obvious story at the
time.

### Tooling added along the way

`PXXDBG=p.dgen:<TemplateName>` prints one template's whole sweep — the window
(`from=`, `tokcount=`) and every group with its arguments, arity and
`paramform`. The window matters because a use outside it and a use inside it
that was classified concrete produce the **identical** symptom: an alias minted
under a name that is really a parameter. Nothing printed the window before, so
the two were indistinguishable from outside.

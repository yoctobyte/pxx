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

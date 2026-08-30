---
slug: bug-p-the-rtl-generics-corpus-stops-on-tkey-in-a-tlist-body
track: P
prio: 55
type: bug
status: backlog
blocked-by: []
summary: "The rtl-generics corpus wall, as of binary d5a35c8de13a: `unknown type: TKey` raised while replaying a `TList<T>` method body, where `TKey` is not a parameter of `TList<T>` and the surrounding tokens still show `SizeOf(T)` with `T` un-substituted. Symptom recorded from a measurement; the mechanism is NOT diagnosed and the obvious story (a body replayed against another template's parameter set) is a hypothesis only. Unmoved by the cross-unit interface-splice fix — it fires before splice placement can matter, so it is the thing actually holding `uses Generics.Collections`."
owner: unassigned
---

# The rtl-generics corpus stops on `TKey` inside a `TList<T>` body

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

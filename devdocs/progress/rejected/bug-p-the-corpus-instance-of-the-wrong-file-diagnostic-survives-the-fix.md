---
slug: bug-p-the-corpus-instance-of-the-wrong-file-diagnostic-survives-the-fix
track: P
prio: 0
type: bug
status: rejected
blocked-by: []
summary: "REJECTED — the premise is false, measured. The corpus diagnostic is CORRECT: `PXXDBG=a.srcmap:*` shows the error token inside `SPLICE start=42607 count=27 src=generics.defaults.pas`, so the tokens really did come from that file. `TKey` occurs zero times there because it is the SUBSTITUTED ARGUMENT, pasted in from a macro in generics.collections.pas — which is what a specialization does. Original (wrong) claim: rtl-generics still reports `unknown type: TKey` in `generics.defaults.pas:78`, a file where `TKey` occurs zero times, on binary a9a4818ab6c8 — AFTER the fix that closed bug-p-a-specialized-body-reports-errors-in-the-wrong-file. The reduction that ticket isolated is genuinely fixed and gated; the corpus instance is not. Two instances were merged on SIGNATURE similarity (same wrong file, same shape, two corpora) and the merge now looks wrong: one reduction's fix does nothing for the other. Do not re-merge on signature."
owner: unassigned
---

# The corpus instance of the wrong-file diagnostic survives the fix

## Measured

Binary `a9a4818ab6c8` — the fixed one, self-host converged, `gate.sh quick`
GREEN, and the reduction's own `test-core` recipe passing:

```
$ pascal26 -dVER3_0_0 -Fu<rtl-generics/src> gcprobe.pas
pascal26:78: error: unknown type: TKey
  in: .../generics.defaults.pas
```

Byte-identical to the pre-fix output. `grep -c TKey generics.defaults.pas` is
still **0**.

## What was fixed, and why it was not this

[[bug-p-a-specialized-body-reports-errors-in-the-wrong-file]] found that the
template arena holds three kinds of region and the provenance lookup scanned
one: buffered generic METHOD bodies (`GenericMethods[]`) were uncovered, so
`TemplateSrcKeyOfTok` returned -1, `PasSpliceTokFile` early-exited, and the
pasted region inherited the destination unit's name. That is real, reduced to
three files, fixed, and gated.

It does not move the corpus. So the corpus reaches its wrong `in:` by a path
that either does not go through `TemplateSrcKeyOfTok` at all, or goes through it
with a key that is present but wrong.

## The merge was made on signature, and signature is exactly what this class of
bug counterfeits

Two instances were folded into one ticket: frank-rust's (rtl-generics probe,
`near:` at `collections.pas:1631`) and frankB's (corpus rung 6b, `near:` at
`:1309-1310`). Both named `generics.defaults.pas`, both showed the "file wrong,
`near:` right" shape, and the agreement across two corpora was read as
strengthening the case. It may instead have been two defects printing the same
counterfeit coordinates — which is the thing the parent ticket proves is
possible, applied to the parent ticket's own evidence.

**Do not re-merge on signature.** Separate by mechanism: put the source-map
instrument on it (`PXXDBG=a.srcmap:*`) and find whether a SPLICE is planted for
the region the error token sits in.

## The supporting evidence is weaker than it reads

The inference "the tokens are really at `collections.pas:1631`" came from
reading `near:`. `near:` is stale after any token splice
([[bug-a-the-near-context-window-is-stale-after-a-token-splice]]), and a
specialization-heavy corpus is nothing but splices, so that inference does not
carry.

What survives with no coordinate in it is the grep: `TKey` occurs 0 times in the
file named and 65 times in `generics.collections.pas`. That proves the
attribution is **wrong**. It does not establish **where** the tokens are, and
every attempt so far to say where has used a field that rides on token indices.

## Suggested first move

`PXXDBG=a.srcmap:*` on the corpus probe, and compare the SPLICE entries against
the token index the diagnostic reports (the probe prints both). The parent
ticket's fix is visible in that dump as a second SPLICE line; if the corpus dump
shows a splice covering the error token and the answer is still wrong, the range
table is being corrupted after the plant rather than never planted — a different
bug with a different owner.

---

# REJECTED — measured, and the premise is false

`PXXDBG=a.srcmap:*` on the corpus probe, binary `a9a4818ab6c8`:

```
PXXDBG a.srcmap SPLICE start=42607 count=27 src=.../generics.defaults.pas resumes=3
PXXDBG a.srcmap tok=42616 srcline=78 -> .../generics.defaults.pas
pascal26:78: error: unknown type: TKey
  in: .../generics.defaults.pas
```

Token 42616 sits inside `[42607, 42634)` — a body **spliced from
generics.defaults.pas**. The file is right. The line is right. The diagnostic
was correct all along, before this fix and after it.

## Why the grep looked like proof and was not

`TKey` occurs zero times in `generics.defaults.pas` **because it is the
substituted argument**, pasted into that file's template from
`generics.collections.pas`. A specialization argument is by definition not in
the template's own text. The grep measured the wrong thing: absence of the
argument in the template file is the expected state, not evidence of
mis-attribution.

Both frankB and I used that grep as the coordinate-free evidence that survived
when line and `near:` were discredited. It was coordinate-free and also
uninformative.

## What manufactured the illusion

The `near:` window
([[bug-a-the-near-context-window-is-stale-after-a-token-splice]]) printed
`ACount * SizeOf(T)` and `[ANewIndex], SizeOf(T)`, which do sit at
`generics.collections.pas:1631`/`:1687`. That is the **stale pre-splice
spelling** at those indices, not the tokens the parser was reading. It pointed
at a real place in the wrong unit, which is the most convincing possible way to
be wrong — a plausible location in a file that really does contain `TKey` 65
times.

So the entire "the corpus names a third unrelated file" story was an artifact of
one broken instrument plus one grep whose null result was preordained.

## Where the real bug went

`bug-p-the-rtl-generics-corpus-stops-on-tkey-in-a-tlist-body` — retitled and
re-diagnosed with this evidence. The `TKey` is a nested specialization
`IEqualityComparer<TKey>` inside a template whose parameter list arrives from a
macro. Nothing about file attribution is involved.

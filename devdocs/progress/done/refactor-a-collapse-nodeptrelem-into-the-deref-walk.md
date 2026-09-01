---
slug: refactor-a-collapse-nodeptrelem-into-the-deref-walk
title: "`NodePtrElem` has no callers left outside the walk that falls back to it"
track: A
prio: 30
type: refactor
blocked-by: []
status: done
owner: frankB
created: 2026-08-30
summary: "DONE 2026-09-01 (frankB). NodePtrElem is deleted and both fallbacks inside ResolveDerefShapeAt keep their defaults instead of asking it. Settled by measurement in BOTH directions, not by a dead-code argument: a full tier with PXXDBG=a.derefwalk hit the two lines 939 and 220 times across 1050 job logs and NodePtrElem answered NONE of them (else-ans=0, backstop-ans=0 on every row), while both fallbacks restored those same defaults on a False return -- so removal is behaviour-preserving wherever it was measured. And the arms-disabled control (:noarms) shows NodePtrElem was the POORER walk: it answers 11356 of 11383 calls and derefshape goes 30/30 to 27/30, so a firing anywhere unmeasured would have OVERRIDDEN a correct default rather than rescued a missing one. The kinds that reach the fallbacks name real work, not a net: AN_PTR_CAST (939) because the cast arm guards on ASTIVal >= 0, AN_IDENT (218) because the ident arm can answer tyUnknown -- filed separately as widen-the-guards, which is where the remaining value is."
---

# What is left of the two-predicates ticket

[[refactor-a-two-predicates-answer-what-a-caret-yields]] made
`ResolveDerefShape` a superset of `NodePtrElem` in shapes, which removed the
harm — swapping a call site no longer trades depth for spellings. It did **not**
collapse the two functions, which was that ticket's stated end state.

## Why it is smaller than it looks, and why it is still not free

`NodePtrElem` has **no external callers**. `15ec54d7a` moved the last one to
`ResolveDerefShape`. Everything reaching it today is inside the walk:

- its own recursion (INDEX base, BINOP operands),
- `ResolveDerefShape`'s final `else`,
- the `tk = tyUnknown` backstop from `bfb7b4c59`.

So the job is not "check every caller"; it is "decide what those two fallbacks
are for". Two things stop a mechanical delete:

1. **Circularity** — both live calls are inside the function that would become
   the wrapper's body.
2. **The contracts differ where it matters.** `NodePtrElem` returns `False` for
   a node it cannot type and both fallbacks branch on that `False`;
   `ResolveDerefShape` answers `tyInteger` instead. Collapsing has to choose one
   and say which.

## The measurement already taken

Counters on both fallbacks and both new arms, built twice (arms on, arms
disabled). With the arms live, `else` and `backstop` are 0 everywhere tried;
with them off, the same counters fire and take exactly the four hits the arms
now take. Full table in the parent ticket.

**That is not enough to delete on.** The population is six files, `compiler.pas`
reads 0 in both columns (so it is evidence about neither), and "I could not
construct a case" describes a search, not the grammar. Whoever picks this up
should widen the population first — a full-tier run with the counters in, which
is a Track T ask — and only then decide delete vs keep.

## 2026-09-01 (frankB): the superset claim re-measured, and a better population than six files

**The parent ticket's end state is confirmed done, by dispatch-arm census rather
than by reading the comment.** Counting only real dispatches (`ASTKind[node] =
AN_x`, comments stripped):

| walk | arms |
| --- | --- |
| `NodePtrElem` | 6 — `AN_IDENT, AN_INDEX, AN_DEREF, AN_FIELD, AN_PTR_CAST, AN_BINOP` |
| `ResolveDerefShapeAt` | 10 — those six **plus** `AN_CALL, AN_CALL_IND, AN_VIRTUAL_CALL, AN_INTF_CALL` |

**Only in `NodePtrElem`: none.** So it is a strict superset in shapes, which is
what `72b4bd51af` ("make the deref walk a superset of NodePtrElem, not its
richer half") set out to do. The remaining risk is entirely the *other*
direction — richer PER SHAPE — which is what both fallbacks exist to cover.

**A caution for the next reader, because I walked into it:** the comment at
`pasparser_lval.inc:~5455` reads as if the asymmetry were current (*"neither a
superset"*). It is **history** — it explains why the swap used to be a silent
trade, and the sentence after it describes the fix. I briefly recorded it as a
stale comment before checking the commit order; `72b4bd51af` (08-30) is LATER
than `f687061dba` (08-25), and it is the one that closed the gap. The comment is
correct and the tense is doing the work. Do not "fix" it.

### The population problem has an answer now

This ticket says the counter measurement is not enough to delete on because
*"the population is six files"*, `compiler.pas` reads 0 in both columns, and
*"'I could not construct a case' describes a search, not the grammar"*. All
still true. But there is now a **targeted** population: `test/derefshape/`,
20 rows = 5 spellings × 4 element kinds, generated from the axes by
`tools/gen_derefshape.py` rather than chosen (`4aa99c240`, `787d353f7`).

**It works even though 13 of the 20 rows crash at runtime, and that is the point
worth writing down:** the two fallbacks fire during COMPILATION, so a row that
SEGVs when run has already delivered its evidence. A runtime failure does not
cost a compile-time counter anything. So the crashing rows are not a limitation
of this population — they are simply irrelevant to it.

Suggested sequence for whoever finishes it (me, after frankA lands):
1. Counters on both fallbacks, as before.
2. Compile all 20 rows plus the six files. That is 20 shapes chosen because they
   are the product of the axes, not because someone thought of them.
3. Arms-disabled control build, to confirm the counters can fire at all — the
   previous run already did this and it is the reason its zero means something.
4. Then decide delete vs keep, and if keep, say what the fallback is FOR.

Still not a grammar argument, and the ticket is right that only a grammar
argument fully settles it. It is a much better search.

### Sequencing

**Not touching `NodePtrElem` or `ResolveDerefShapeAt` until frankA lands
`bug-a-p-caret-index-...-plain-identifier`.** Their carriers are mid-flight in
the same two walks, and the collapse changes the walk every managed-string and
PChar predicate routes through — which would confound their A/B on the faces
whether or not I am the one who commits it.

# Gate

Track A: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`, plus
`test/test_deref_shape_through_arith_and_nonident_base.pas` and the three cast
/deref tests the parent ticket pins. The failure mode here is a wrong VALUE, not
a red, so a counter-instrumented full-tier A/B is worth more than any local run.

## 2026-09-01 (frankB): measured at scale, with a control that ships

The previous entry said the counter measurement was *"not enough to delete on"*
because the population was six files and *"'I could not construct a case'
describes a search, not the grammar"*. Both still true. What changed is that the
search is now much larger, the instrument is permanent, and — the part that was
missing — **it has a positive control that anyone can run in one command.**

`PXXDBG=a.derefwalk:*` is the real column. `PXXDBG=a.derefwalk:noarms` makes
`DwDispatchKind` answer a kind no arm tests for, so every node falls past the ten
typed arms and the counters MUST fire. A zero in the real column means something
only beside that.

| | calls | `else` | `else-ans` | `backstop` |
| --- | --- | --- | --- | --- |
| 35 files, arms live | 11400 | **0** | 0 | **0** |
| 35 files, arms disabled (control) | 11383 | 11383 | 11356 | 0 |
| `compiler.pas`, arms live | 447 | **0** | 0 | **0** |

The 35 are the 30 generated `derefshape` rows (now write AND read face),
`test_deref_shape_*`, `test_cast_deref_chain_siblings`, the new
`test_index_through_record_pointer_cast`, and frankA's `test_nd_subarray_as_param`.

**The backstop does not fire on `test_cast_deref_chain_siblings` — the regression
it was added for.** An arm claims that shape now. That is the single most
interesting number here and it is the one most worth a second source.

### The behavioural A/B, which is worth more than the counts

A count cannot see the direction this ticket actually has to choose, because the
two walks disagree by ANSWER, not by whether they answer. So: run the population
with the arms disabled and look at the OUTPUT.

NodePtrElem answers 11356 of 11383 calls — it declines almost nothing — and
`derefshape` goes from **30/30 to 27/30**: `ds_nested_fixdbl`, `ds_nested_md2`
and `ds_cast_ptrelem` turn silently wrong (`0.00 6.00` where `6.00 6.00` belongs,
and an 8-byte read where a 4-byte element belongs).

So `NodePtrElem` is not a candidate to BE the walk, and the collapse can only run
one way: the arms are the answer, and the question is only whether the two
fallbacks under them are reachable at all. **It also means a fallback that DOES
fire somewhere unmeasured is not obviously better than the `tyInteger` default it
guards** — it is the poorer walk answering, which is a different argument from
"the fallback is a safety net".

### What is still missing, stated as a job rather than a caveat

One full-tier run with `PXXDBG=a.derefwalk:*` in the environment. That is Track
T's tier, not mine, and it now costs one env var and a `grep`. Both fallbacks
print `kind=<n>` when they fire, so a nonzero comes back diagnosed instead of
starting a second investigation.

If that run is also zero, delete both fallbacks and `NodePtrElem` with it — it
has no external callers (`15ec54d7a` moved the last one) and nothing else would
reach it. If it is nonzero, the printed kinds name the arms to add, and the
fallbacks stay until they are added.

**Not deleting on my own population.** A generated product over two axes plus the
compiler is a good search and is still a search; this file has already recorded
one wrong root cause that came from reasoning where a measurement was available,
and "I could not construct a case" is exactly that shape one level up.

## 2026-09-01 (frankB): done — and the full-tier run changed the answer

The entry above this one said the fallbacks fire 0 times in 11847 calls across 35
files and that this was *"a search, not a grammar argument"*. It was right to
withhold the deletion, and the widening it asked for **overturned its zero**:
on a full tier the two lines fire **1159 times**. Deleting on the 35-file zero
would have been deleting live code on a measurement that had simply not looked
far enough.

What made the deletion safe was not a bigger zero. It was a different column:

| | firings | NodePtrElem answered |
| --- | --- | --- |
| full tier (1050 job logs) | else 939, backstop 220 | **0** |
| 35 files + compiler.pas | 0 | — |

Both fallbacks already restored their defaults when NodePtrElem returned False.
`ans=0` everywhere therefore means **removing the call is behaviour-preserving on
every case measured** — a stronger claim than "unreachable", and one that
survives the code being reached 1159 times.

### The control is what stops this being a safety-net argument

`PXXDBG=a.derefwalk:noarms` disables the ten typed arms. NodePtrElem then answers
11356 of 11383 calls — it declines almost nothing — and `test/derefshape` goes
**30/30 to 27/30**: `ds_nested_fixdbl`, `ds_nested_md2` and `ds_cast_ptrelem` turn
silently wrong. So it was the POORER walk, and a fallback of it firing somewhere
unmeasured would have overridden a correct `tyInteger` default with a worse
answer. The thing that read as a net was the opposite of one.

### What is actually left, which is the useful half

The fallbacks are still reachable and now simply keep their defaults. The two
kinds that reach them name work:

- **`AN_PTR_CAST`, 939 hits** — the cast arm guards on `ASTIVal >= 0`, so the
  adapter casts (ival -1/-2) fall past it.
- **`AN_IDENT`, 218 hits** — the ident arm can answer `tyUnknown`, e.g. an
  untyped `Pointer`.

Widen those two guards. That is a different ticket and a real one; this one was
about whether a second walk had to exist, and it does not.

### Method note for whoever inherits this file

Three times in this ticket a zero was the wrong answer, each for a different
reason: a counter that had never been observed nonzero (fixed with `:noarms`);
a probe that never reached the jobs at all (testmgr's env allowlist keeps `PXX_`
and the variable is `PXXD`); and a population too small to contain the case
(fixed by the full tier). **Every one of them printed a clean zero under a green
gate.** The zeros were only worth reading once each had a control that made it
possible for them not to be zero.

## 2026-09-01 (frankB): verified on a quiescent full tier

Three full tiers were run. **The first two verdicts were void and neither RED was
real** — worth recording, because the failure was mine and it is not the one the
rules warn about:

- run 1: I rebuilt the compiler mid-run while fixing an unrelated RED. testmgr
  flagged the swap itself (`compiler/pascal26 changed during this run`).
- run 2: I ran `git pull --rebase` mid-run and picked up two `compiler/**`
  commits. Every `tools/compiler_srchash.sh compiler/.pascal26.fixedpoint` job
  failed — seven job groups — because the stamp was written for the sources the
  tier started with and the tree moved underneath it.

CLAUDE.md says to rebuild after any sync touching `compiler/**` *before you
measure*. I had only ever read that as being about a binary I was about to run.
**A full tier is a fifteen-minute measurement, and the tree must not move for the
whole of it.**

Run 3, quiescent tree, binary `f121f3de4811`, nothing pulled or committed during
it:

- **one** failure, `test-xtensa#122` — a forward CALL0/CALL8 range overflow
  building an xtensa image. Not mine, by three independent sources: it failed in
  the PRE-deletion tier too, it is already filed as
  [[feature-a-xtensa-should-not-need-a-flag-to-build-a-large-image]], and seven
  has reported it across several shas tonight.
- the fallback census is **identical to the pre-deletion run**: else 939,
  backstop 220, and the same four kinds (AN_PTR_CAST 940, AN_IDENT 218, one
  AN_FIELD, one AN_CALL). The deletion changed nothing about which nodes reach
  those lines, which is exactly what "the caller restored the same default when
  it declined" predicts.

**One honest caveat on the instrument, since this file is about not trusting
zeros.** After the deletion the `-ans` columns can only read 0 — there is no call
left to answer — so they are no longer evidence of anything and a run that shows
them is not confirming the deletion. The `-ans` evidence is entirely the
PRE-deletion tier. What the post-deletion run confirms is the hit counts and the
kinds, which are live numbers, and the absence of a new failure.

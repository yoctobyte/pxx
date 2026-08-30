---
slug: bug-p-generic-type-param-unresolved-in-class-abstract-template
track: P
prio: 70
type: bug
blocked-by: []
status: working
created: 2026-08-30
summary: "A generic template's own type parameter is not in scope inside a `class abstract(...)` body: generics.collections' TCustomPointersEnumerator<T, PT> reports `unknown type: PT` for its own PT. This is the wall the rtl-generics corpus hits now that bug-p-object-value-types-standard-meaning cleared the one 26 lines later that used to abort the parse first."
owner: frankR
---

# P: a generic type parameter is unresolved inside a `class abstract` template

## Repro

From `library_candidates/rtl-generics/packages/rtl-generics/src`, with a
one-line program that only does `uses Generics.Collections`:

```
pascal26:120: error: unknown type: PT
  in: generics.collections.pas
  near: class abstract protected function DoGetCurrent  >>> PT  virtual
pascal26:123: error: unknown type: PT
  near: abstract  public property Current  >>> PT read DoGetCurrent
pascal26:135: error: unknown type: TArray
  near:  ACount  SizeInt   >>> TArray  UInt32
pascal26:135: error: unexpected token
```

The declaration at :120 is:

```pascal
TCustomPointersEnumerator<T, PT> = class abstract(TEnumerator<PT>)
protected
  function DoGetCurrent: PT; virtual; abstract;   { <-- PT unknown here }
public
  property Current: PT read DoGetCurrent;
end;
```

`PT` is the template's OWN second type parameter. It resolves in the ancestor
clause (`TEnumerator<PT>` is accepted) and not in the member bodies.

## Why it surfaced only now

It did not regress; it was unreachable. `pinned` aborts at :146 on
`TCustomPointersCollection<T, PT> = object`, a *syntactic* error 26 lines
LATER, and the parse stops there before any specialization is streamed — so
these semantic errors, which are reported against the template's own line
numbers when the specialization is instantiated, never got a chance to fire.
Clearing :146 (`bug-p-object-value-types-standard-meaning`, this session) makes
:120 the live wall.

That ordering is worth keeping in mind for the corpus generally: an *earlier*
line number in the error output does not mean an earlier failure, and "the wall
moved backwards" is the expected shape after a syntax fix, not a regression.

## Scope

Two distinct-looking symptoms, possibly one cause — establish which before
fixing (root-cause-over-microfix):

1. `PT` unknown in member signatures / property types of the template body;
2. `TArray` unknown at :135, inside `class procedure` parameters — `TArray<T>`
   is itself a generic alias, so this may be the same scope gap one level up
   rather than a second bug.

Vary the shape first: does a two-parameter `class` (not `abstract`) template see
its second parameter? Does a one-parameter one? Is it `abstract` that matters, is
it the second parameter specifically, or is it any parameter used in a member
whose ancestor clause also mentions it?

## Consequences

- This is the current blocker for rung 6 of [[feature-pascal-corpus-expansion]]
  (p75); it inherits that priority, which is why this sits at 70.
- Filed from [[bug-p-object-value-types-standard-meaning]], which cleared the
  previous wall and whose before/after measurement is in its commit.

## 2026-08-30 (coordinator) — RUN THIS BEFORE YOU START: `:120` may be an artefact of the probe

This ticket's title and summary rest on `pascal26:120: error: unknown type: PT`.
**That line is reproducible under one probe and absent under another**, and the
two probes were run by two lanes on the same day against the same file:

| probe as recorded | binary | first stop |
| --- | --- | --- |
| *"a one-line program that only does `uses Generics.Collections`"* (this ticket, frank-user) | **sha not recorded** | `:120` `unknown type: PT`, then `:123`, then `:135` |
| `{$mode delphi}` program, `uses Generics.Collections`, `-Fu<rtl-generics/src>` (frank-rust) | HEAD `ea5a8ef96`, binary `6319b892f517` | `:135` `unknown type: TArray`; **`:120` never appears** |

**These are the SAME probe and they disagree.** No compiler commit separates the
two binaries (`git log d23f52948..ea5a8ef96 -- compiler/` is empty), so a code
change between the runs does not explain it either.

Under the second probe, `TCustomPointersEnumerator<T, PT> = class abstract(TEnumerator<PT>)`
resolves `PT` fine. **The corpus reaches this unit the second way**, so if the
difference is real the wall this ticket names is not the wall the corpus hits.

**RETRACTED, same day, by the coordinator who wrote it.** This paragraph proposed
compiling the unit directly with `{$mode delphi}` forced, on the theory that a
directly-compiled unit does not inherit the mode of a program that `uses` it. Two
things kill it, and both were free:

- **`generics.collections.pas:29` is `{$MODE DELPHI}{$H+}`** — the unit sets its
  own mode. `sed -n 29p` answers it; I proposed a build instead.
- **pxx refuses standalone units outright.** Verified on an unrelated file:
  `pinned lib/rtl/aesgcm.pas` → `pascal26:2: error: this file is a unit, not a
  program`. The direct probe does not exist, so it cannot be the variable.

**The real state: both lanes ran the same probe and disagree, and nothing
explains it.** The remaining candidates are an unrecorded flag or a binary that
was not the sha its lane believed — which only the lane with the shell history can
check.

**DO NOT RETITLE THIS TICKET YET.** frank-rust asked for that hold and is right:
retitling on the strength of its `:135` is the same move as it adopting `:120` on
mine, in the other direction. The ticket may be correctly named and simply
unreachable by one probe, or it may rest on a run nobody can reproduce. **It needs
one working, pasted-from-the-shell probe first, and the person who can produce one
is the person who saw `:120`.**

If `:120` turns out not to reproduce, the real subject is `:135`: `TArray<T> =
array of T` is declared at `:57` of the same file, so a generic **array** template
fails to resolve where a generic **class** template at `:133` succeeds — a
different defect wanting a different title.

**Do not resolve the discrepancy by picking the number you saw first.** Two
careful lanes measured different walls and neither was wrong; the reconciliation
is in `feature-pascal-corpus-expansion`'s entry for today. State the probe, the
sha and the binary in whatever you write here — a bare line number in a corpus
ticket is a fact about a probe nobody recorded.

## 2026-08-30 (frank-rust, narrowing) — FOUR candidates eliminated, and a subset signal

All on HEAD `ea5a8ef96` / binary `6319b892f517`, each with its command in
frank-rust's own closed ticket:

| candidate | check | result |
| --- | --- | --- |
| the probe program's `{$mode delphi}` | directive removed | still `:135` |
| the probe program's mode **flag** | `-Mobjfpc` added | still `:135` |
| a compiler change between the runs | `git log d23f52948..ea5a8ef96 -- compiler/` | **0 commits** |
| a different **copy** of the corpus | 3 copies compared | byte-identical, `sha256 5a3402725ab53181` |

The mode candidate was frank-rust's own uncontrolled variable — its probe carried
`{$mode delphi}` and the other is described as a bare one-liner — **introduced
while arguing that probes must be stated exactly, and killed by the lane that
introduced it.**

### THE SIGNAL THAT DISCRIMINATES: `:135` IS A STRICT SUBSET, NOT A DIFFERENT ANSWER

frank-user's run reports `:120`, `:123` **and** `:135` — a list. frank-rust's
reports `:135` alone.

> **A different probe generally yields a different FIRST error. What it does not
> usually yield is the same error with two extra ones in front of it.** A
> different *binary* — one that reports semantic errors the other never reaches or
> does not emit — produces exactly that nesting.

Weak, and recorded as weak. But it is the first evidence that discriminates
between the two surviving hypotheses, and it favours **wrong binary** over
**unrecorded flag**. Concretely: a build taken mid-change, before the final
commit, would report more.

**The last step needs frank-user's shell history** — which binary it actually ran.
Nobody is chasing it during the pre-merge pause; it is a p70 backlog item and the
question is one message when work resumes.

## 2026-08-30 (frankR) — `:120` does not reproduce on `pinned` either; `:135` root-caused and it is not a parser bug

Everything below is one pasted probe, stated exactly as the hold above demands.

```
HEAD           097f9b794
binary         compiler/pascal26   sha256 f92f3c013ac58cda
pinned         stable_linux_amd64/default/pinned  sha256 abece5150983d95e
corpus         generics.collections.pas  sha256 5a3402725ab53181  (same file all lanes measured)

$ cat gcprobe.pas
program gcprobe;
uses Generics.Collections;
begin
end.

$ pascal26 -Fu<rtl-generics/src> gcprobe.pas gcprobeo
```

Note the flag ORDER: `-Fu` after the source file is silently ignored and the run
dies at `:2 uses: unit source not found`. That is a plausible way to record a
probe that did not do what its author thought.

### `:120` — a THIRD recorded run, and this one is on `pinned`

| binary | first stop | `:120` present? |
| --- | --- | --- |
| `6319b892f517` (frankR, earlier session) | `:135` | no |
| `f92f3c013ac58cda` (frankR, HEAD 097f9b794) | `:135` | no |
| **`abece5150983d95e` (`pinned`)** | **`:135`** | **no** |

The third row is the new information. `pinned` is the OLDER binary — so if some
build in this checkout's history reported `unknown type: PT` at `:120`,
`pinned` was the candidate, and it does not. `TCustomPointersEnumerator<T, PT>
= class abstract(TEnumerator<PT>)` resolves `PT` on every binary available here.

**Still not retitling** — the hold stands and the missing piece is unchanged: it
needs frank-user's shell history, not another run from me. But the "unrecorded
flag vs wrong binary" split now has a third data point on the `wrong binary`
side, and the flag-order trap above is a concrete mechanism for how the `:2`
failure mode hides.

### `:135` — root cause found, and the ticket's own hypothesis is disproved

The note above reads: *"`TArray<T> = array of T` is declared at `:57` of the
same file, so a generic **array** template fails to resolve where a generic
**class** template at `:133` succeeds."*

`:57` is **inside an `{$ifdef}`**:

```pascal
  {$ifdef VER3_0_0}
  TArray<T> = array of T;
  {$endif}
```

and pxx defines `VER3`, `VER3_2`, `VER3_2_2` (`lexer.inc:1188-1190`) — **not**
`VER3_0_0`. So that declaration is skipped, and the corpus is doing the right
thing: from FPC 3.0.2 on, `TArray<T>` comes from the `System` unit. **pxx claims
VER3_2_2 and its RTL provides no `TArray`** — `grep -rn TArray lib/ --include=*.pas`
returns nothing.

Decisive experiment — define the symbol so the corpus declares it itself:

```
$ pascal26 -dVER3_0_0 -Fu<src> gcprobe.pas gco2
pascal26:214: error: unexpected token
```

`:135` is **gone** and the wall advances 79 lines. So a generic ARRAY template
resolves perfectly well; there was simply no `TArray` to resolve. The
class-vs-array framing was the wrong split.

**This re-lanes.** `TArray<T> = array of T` in the RTL is a **Track B** library
gap, not a Track P parser defect — one declaration, and the FPC-parity argument
for it is that pxx already answers `VER3_2_2` to the `{$ifdef}` the corpus uses
to decide whether to declare it itself. Filed separately rather than taken:
`lib/rtl` is not this lane's file.

### The wall after that is a real Track P generic bug

With `TArray` supplied, `:214`:

```pascal
  TCustomListWithPointers<T> = class(TCustomList<T>)
  public type
    TPointersEnumerator = class(TCustomPointersEnumerator<T, PT>)
    protected
      FList: TCustomListWithPointers<T>;     { <-- :214 }
```

```
near: protected FList  TCustomListWithPointers$UInt32  UInt32 >>>  FIndex
```

The token stream shows `TCustomListWithPointers$UInt32` followed by a stray
`UInt32` — the ENCLOSING template's name was substituted to its specialized
form AND its `<T>` argument list was left behind and substituted separately, so
the field type came out as `TCustomListWithPointers$UInt32<UInt32>`. A nested
class naming its enclosing template is substituted twice.

That one IS this lane's, and it is in `pasparser_generic.inc`.

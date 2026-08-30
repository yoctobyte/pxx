---
slug: bug-p-a-nested-class-naming-its-enclosing-template-is-substituted-twice
track: P
prio: 70
type: bug
blocked-by: []
status: done
created: 2026-08-30
summary: "A nested class inside a generic template that names the ENCLOSING template as a type gets substituted twice -- the name to its specialized form AND the leftover `<T>` argument list separately -- so `FList: TCustomListWithPointers<T>` comes out as `TCustomListWithPointers$UInt32<UInt32>`. Wall at generics.collections.pas:214, reached once TArray is supplied."
owner: frankR
---

# P: a nested class naming its enclosing template is substituted twice

## Repro

`library_candidates/rtl-generics/.../generics.collections.pas:214`, reached with
`-dVER3_0_0` (which supplies the `TArray` the RTL is missing — see
[[bug-b-rtl-provides-no-tarray-generic-but-pxx-claims-ver3-2-2]]):

```pascal
  TCustomListWithPointers<T> = class(TCustomList<T>)
  public type
    TPointersEnumerator = class(TCustomPointersEnumerator<T, PT>)
    protected
      FList: TCustomListWithPointers<T>;     { <-- :214 }
      FIndex: SizeInt;
```

```
pascal26:214: error: unexpected token
  near: protected FList  TCustomListWithPointers$UInt32  UInt32 >>>  FIndex
```

## Diagnosis

Read the token stream in the `near:` line: `TCustomListWithPointers$UInt32`
followed by a **stray** `UInt32`. The field's declared type
`TCustomListWithPointers<T>` was rewritten twice —

1. the NAME `TCustomListWithPointers<T>` matched the enclosing template and was
   replaced by its specialized name `TCustomListWithPointers$UInt32`, and
2. the `<T>` argument list was *not consumed by that rewrite*, so the ordinary
   parameter substitution then turned its `T` into `UInt32` separately,

leaving `TCustomListWithPointers$UInt32<UInt32>` — a specialized name with an
argument list still attached, which is not a type.

Either rewrite alone is correct. The defect is that both run.

## Before closing: CHECK THE SIBLING

`devdocs/dev/normalise-dont-special-case.md` — if the enclosing template's name
is double-substituted through a nested CLASS field, look for the same shape
reachable another way before calling it fixed:

- a nested **record** naming the enclosing template;
- a nested **type alias** (`TSelf = TCustomListWithPointers<T>;`);
- a **method return type** or parameter naming the enclosing template;
- the enclosing template named in a nested class's **ancestor** clause;
- the same, one level deeper (nested inside nested).

Read each; do not assume the fix generalises and do not assume it does not.

## When it lands

Record where the wall moves to. A corpus that fails further on is progress worth
recording even when the next wall belongs to another lane.

Split out of [[bug-p-generic-type-param-unresolved-in-class-abstract-template]],
whose own premise is parked pending frank-user's shell history; this part is
independent of that question.

## 2026-08-30 (frankR) — fixed; and the title is too narrow

### The title says "nested class". The measurement says nesting is irrelevant.

Varying the shape first, per `devdocs/dev/root-cause-over-microfix.md`, before
touching anything. All mode-delphi, all failing IDENTICALLY with the
`TOuter$LongInt  LongInt` signature:

| shape | | before |
| --- | --- | --- |
| `n1` nested CLASS field — the shape the ticket names | `TInner = class FList: TOuter<T>` | FAIL |
| **`n3` plain self-referential field, NOT nested at all** | **`FNext: TOuter<T>`** | **FAIL** |
| `n4` nested RECORD field | `TInner = record FList: TOuter<T>` | FAIL |
| `n5` nested TYPE ALIAS | `TSelf = TOuter<T>` | FAIL |
| `n2` the same thing in mode OBJFPC | `FList: specialize TOuter<T>` | **passes** |

`n3` is the one that matters: **a self-referential generic — the linked-list /
tree-node idiom, the single most common shape a generic container takes — was
broken in mode delphi**, with no nesting anywhere. The ticket found it through a
nested class because that is where rtl-generics happened to hit it first.

`n2` passing is what localises it: the objfpc spelling carries the literal
`specialize` keyword and works; the delphi spelling does not and fails.

### Root cause

`NestedSpecGroup` — the function that collapses a nested generic use down to the
single identifier naming its specialization — **requires the literal
`specialize` keyword** as its very first test:

```pascal
if not CaseEqual(GetTokenStrFromRaw(...), 'specialize') then Exit;
```

Mode-delphi code never writes one, so the group was never recognised, and
control fell through to the plain self-name rewrite in `SpecializeToBuffer`,
which replaces the template's own name with the specialization's name **without
consuming a following argument list**. Both rewrites then ran: the name became
`TOuter$LongInt`, and the surviving `<T>` had its `T` substituted by the ordinary
parameter pass — emitting `TOuter$LongInt<LongInt>`, which is not a type.

### Fix

`SelfSpecGroupEnd` in `pasparser_generic.inc`: at the self-name rewrite, if the
name is followed by `<` naming this template's own parameters **in order**,
closed by `>`, skip the group — `specName` already carries the arguments.

Matching the parameters *in order* is the guard that keeps this from eating a
reference to a DIFFERENT specialization of the same template. Verified from both
sides below.

### Verified

All five original shapes compile **and run**; `n6` (method return type AND
parameter, plus the `TOuter<T>.Clone` method-implementation header) prints its
value; `n7` (nested inside nested inside) passes.

**Negative cases — checked against `pinned`, because a negative result is only
evidence if it is not simply a pre-existing failure:**

| | pinned | HEAD | verdict |
| --- | --- | --- | --- |
| `n8` `FOther: TOuter<ShortInt>` inside `TOuter<T>` | FAIL | FAIL, same error | pre-existing, NOT a regression |
| `n9` `FSwap: TPair<V, K>` inside `TPair<K, V>` | FAIL | FAIL | pre-existing |
| **`n10` `FBox: TBox<ShortInt>` — a DIFFERENT template** | **ok** | **ok, runs** | control: unaffected |

Neither `n8` nor `n9` shows the double-substitution signature, so the order guard
did its job; they fail for an unrelated and older reason. `n10` bounds it from
the other side.

That leaves a sharp, pre-existing gap worth its own ticket: **a reference to a
different specialization of the SAME template, from inside that template's own
body** (`n8`, `n9`). Different template, any args: fine. Same template, same
args: fixed here. Same template, different args: still broken, and was before.

Gate: `make compiler/pascal26` converged, `b3c6858bdfbb`. The generic-constraint
corpus is unchanged at 34/36, so this did not disturb yesterday's work.

### Where the wall moved

Probe as before — `program gcprobe; uses Generics.Collections;`, binary
`b3c6858bdfbb7efd`, corpus `5a3402725ab53181`, and note that `-Fu` must precede
the source file or it is silently ignored:

| | before this fix | after |
| --- | --- | --- |
| `-dVER3_0_0` (TArray supplied by hand) | `generics.collections.pas:214` | **`generics.defaults.pas:78` — a DIFFERENT FILE** |
| no flags (the corpus's real state) | `generics.collections.pas:135` | `:135`, unchanged |

`generics.collections.pas` now parses through to the end and the compile carries
on into `generics.defaults.pas`. The second row is unchanged on purpose: `:135`
is the missing-`TArray` gap, which is
[[bug-b-rtl-provides-no-tarray-generic-but-pxx-claims-ver3-2-2]]'s to close, and
nothing here touches it.

The new wall is `unknown type: TKey` at `generics.defaults.pas:78`, then `:79`,
then back in `generics.collections.pas:57`. **That is a type parameter going
unresolved — the same FAMILY as the parked
[[bug-p-generic-type-param-unresolved-in-class-abstract-template]], though at a
different site and reached only with `TArray` supplied.** Whoever picks it up
should read it as a fresh measurement rather than as confirmation of that
ticket's `:120`, which still does not reproduce on any binary here.

## Log
- 2026-08-30 — resolved, commit f02f2c79c.

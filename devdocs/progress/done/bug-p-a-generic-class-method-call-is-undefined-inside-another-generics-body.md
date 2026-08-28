---
prio: 60
track: P
owner: frankA
status: working
---

# `TGeneric<T>.ClassMethod` is "undefined variable" inside another generic's body

- **Type:** bug (spurious error on a valid construct) — **Track P** (Pascal
  frontend, generics).
- **Pre-existing:** reproduces identically on **pinned**.
- **Found by:** compiling `rtl-generics` (corpus rung 6) — see
  [[feature-pascal-corpus-expansion]]. Second of the two Track P walls in
  `generics.defaults.pas`; **not** typinfo.
- **Binary:** `2c4e727d4b63`, verified self-host fixedpoint at `4f380892c`.
- **Sibling:**
  [[bug-p-a-generic-methods-out-of-line-header-binds-to-a-same-named-non-generic-class]].

## Symptom

Calling a class method on a generic that is specialized *inline* by the
**enclosing** generic's own type parameter — `TCmp<T>.Default` written inside
the body of `TOrd<T, U>` — is rejected with `undefined variable (TCmp)`. The
name is read as a variable rather than as a type being specialized, so the
`<T>` is never consumed.

## Repro (24 lines; FPC prints `8`, pxx errors)

```pascal
program s1;
{$MODE DELPHI}{$H+}
type
  TCmp<T> = class
    class function Default: LongInt; static;
  end;

  TOrd<T, U> = class
    class function Get: LongInt; static;
  end;

class function TCmp<T>.Default: LongInt;
begin
  Result := SizeOf(T);
end;

class function TOrd<T, U>.Get: LongInt;
begin
  Result := TCmp<T>.Default;   // <-- pascal26: undefined variable (TCmp)
end;

type TO1 = TOrd<Int64, LongInt>;
begin
  WriteLn(TO1.Get);
end.
```

## Why it matters

This is the standard way `rtl-generics` reaches a comparer:

```pascal
class constructor TOrdinalComparer<T, THashFactory>.Create;
begin
  FEqualityComparer := TEqualityComparer<T>.Default(THashFactory);
  FComparer := TComparer<T>.Default;
end;
```

13 expression-position uses in `generics.defaults.pas`; the shape appears
~357 times across `generics.collections.pas`, so it is very likely the dominant
wall on rung 6's larger unit as well. Worth confirming that count against
`generics.collections.pas` once this and the sibling are fixed — that grep
counts implementation headers too, which are fine.

## Note on scope

`TCmp<T>.Default` where `T` is a *concrete* type resolves fine. The failure
needs `T` to be the enclosing generic's parameter, i.e. the specialization is
itself still a template at the point of use.

---

## Diagnosis banked, ticket parked (2026-08-28, frankA)

Reproduced, root-caused, and **reclassified** — but not fixed. Parking with the
diagnosis rather than landing a microfix, per `root-cause-over-microfix.md`. All
speculative edits were reverted; the tree is at a verified fixedpoint
(`c264c81a0d5a`) with no partial work in it.

### This is not a Delphi-surface bug, and the ticket title understates it

The decisive measurement: the same construct written by hand in **objfpc**, with
no Delphi rewrite involved anywhere, fails **on the pinned binary**:

```pascal
{$mode objfpc}{$H+}
type
  generic TCmp<T> = class
    class function Default: LongInt; static;
  end;
  generic TOrd<T, U> = class
    class function Get: LongInt; static;
  end;
class function TCmp.Default: LongInt; begin Result := SizeOf(T); end;
class function TOrd.Get: LongInt;
begin
  Result := (specialize TCmp<T>).Default;   { pinned: undefined variable (specialize) }
end;
type TO1 = specialize TOrd<Int64, LongInt>;
begin WriteLn(TO1.Get); end.
```

So the real defect is: **a nested `specialize X<T>` group is not supported in
EXPRESSION position.** Parenthesised or bare, both fail. The mode-Delphi
spelling merely reaches it by a different route and reports a different message.
Retitle when picking this up.

### Two stacked defects, in order

**(a) The rewrite misclassifies the use as a method-impl header.**
`DelphiRewriteGenericUses` (`pasparser_generic.inc`) decides "is this a method
implementation header?" by testing what **follows** the group — a dot:

```pascal
if (j + 1 < TokCount) and (Tokens[j + 1].Kind = tkDot) then
  RemoveTokens(i + 1, j - i)   { method impl reference }
```

But `TCmp<T>.Default` in expression position also has a dot after the group, so
it is treated as a header and has its `<T>` deleted — leaving a bare template
name, hence `undefined variable (TCmp)`. A header is identified by what
**precedes** the name (`procedure` / `function` / `constructor` / `destructor`,
optionally after `class`), not by what follows it. Note `constructor` and
`destructor` are SOFT keywords here — compared by text, delivered as `tkIdent`
(`pasparser_class.inc:26`).

Correcting this alone is *not* a fix: it routes the use into the `specialize`
arm, where it then hits (b) and reports `undefined variable (specialize)`. That
is the honest state — both surfaces converge on the same underlying gap — but it
is not a user-visible improvement, which is why it was not landed on its own.

**(b) The nested-specialization prerequisite scan never looks inside method
bodies.** In `ParseSpecialization`, the scan that collects nested
`specialize NAME<args>` prerequisites sweeps only:

```pascal
ts := Templates[ti].TokStart;
tc := Templates[ti].TokCount;
```

i.e. the **class body**. Method bodies are buffered separately by
`BufferGenericMethod` into `GenericMethods[]`. A nested specialization that
appears *only* inside a method is therefore never registered, no alias
declaration is emitted, `SpecializeStream`'s collapse finds `NestedSpecKnown`
false, and the literal word `specialize` survives into the stream — which is
exactly the error text.

### What was tried, and where it stopped

Extending the scan to `for gmScan := -1 to GenericMethodCount - 1` (−1 = class
body, ≥0 = each buffered method with `TemplateIdx = ti`) **does** change
behaviour — the prerequisite is created and the alias declaration is emitted —
but the streamed alias then fails differently:

```
error: expected method name    near: Int64  class class function >>> Default
```

i.e. the alias's own class body streams as
`TCmp$Int64 = class class function Default: LongInt; static; ... end;` and the
class-body parser rejects the `class function` member in that position, even
though the identical member parsed fine in the original template. That is a
third thing, not understood, and chasing it is where this stopped.

**So the scan extension is necessary but not sufficient.** Anyone picking this
up should expect to fix (a), (b), and whatever that third failure is, and should
treat the objfpc repro above as the primary case — it is smaller, has no rewrite
in the way, and fails on `pinned`.

### Not to be confused with

[[bug-p-a-generic-methods-out-of-line-header-binds-to-a-same-named-non-generic-class]]
(fixed, `042bcbb32`) touched the same arm of the same function but is a
different defect: that one was about *which class* a genuine header binds to;
this one is about a use that is not a header at all.

**Status:** done

---

## 2026-08-28 (frankA) — objfpc FIXED; Delphi mode blocked on an ORDERING defect

**Wall 3 and wall 6 are the same defect, confirmed from the diagnosis rather
than from the numbering.** The corpus ticket's snapshot tables number them
inconsistently (one snapshot already had them as one row), so the question was
asked of the two DEFECTS: this ticket's own banked analysis concludes the real
bug is *"a nested `specialize X<T>` group is not supported in EXPRESSION
position"*, which is verbatim wall 3's subject. One defect, two entries. Wall 3
has no ticket of its own; this is it, and no new one is needed.

### The three stacked defects, all now resolved or reclassified

**(a) header misclassification — FIXED.** `DelphiRewriteGenericUses` identified
a method-implementation header by the dot that FOLLOWS the group, which
`TCmp<T>.Default` in expression position also has. It now tests what PRECEDES
the name (`procedure` / `function` / `constructor` / `destructor`, the last two
compared by text as soft keywords). As the banked note predicted, this alone
moved the Delphi surface onto the same error as objfpc — both now converge.

**(b) the prerequisite scan never saw method bodies — FIXED.**
`ParseSpecialization`'s scan swept `Templates[ti]` only; it now sweeps the class
body **and** every buffered `GenericMethods[]` body of the template (`gmScan`,
-1 = class body).

**(c) the "third thing, not understood" — was NOT about generics at all.**
Isolated to eight lines with no generic in sight: **a method could not be
NAMED `Default`**, because `default` lexes as its own token kind and
`IsMethodNameTok` did not accept it. Fixed, filed as its own concern, and
`IsMethodNameTokAt` — whose comment claimed it shared the predicate "so the two
cannot drift" while carrying a private copy of the list — now actually shares
it. `Default` was the drift that mattered. This is why the failure looked like a
generics bug: `TComparer<T>.Default` is where it surfaced.

### Result

```pascal
{$mode objfpc}
class function TOrd.Get: LongInt;
begin
  Result := specialize TCmp<T>.Size;   { was: undefined variable (specialize) }
end;
```
now compiles and matches FPC. Pinned in
`test/test_generic_nested_specialize_in_method_body.{pas,expected}`, which fails
on `pinned`.

### What still blocks the corpus, and it is a DIFFERENT defect

`generics.defaults.pas` is `{$MODE DELPHI}`, and the Delphi surface still fails
— **not** on (a) or (b), but on an ordering problem underneath both. Measured
with `--debug`:

| mode | trace |
| --- | --- |
| objfpc | `SCAN ti=1 gm=1 …` → `SPEC TO1 = TOrd nested=1` → `needs TCmp$Int64` |
| Delphi | `SCAN ti=1 gm=-1 … (GenericMethodCount=0)` → `SPEC … nested=0` |

**`GenericMethodCount` is 0 when the Delphi specialization runs.** The rewrite
emits its alias declarations near the top of the token stream, so
`ParseSpecialization` executes *before* the parser has reached the method
implementations and buffered them — even though those implementations appear
EARLIER in the source than the user's own specialization. Extending the scan
cannot help: at that moment there is nothing to scan.

So the remaining work is not "scan more", it is **when the Delphi alias is
specialized relative to method buffering**. A deferral mechanism already exists
in `ParseSpecialization` (the `NSpecCount > 0` path), which is the obvious thing
to look at first — deferring a Delphi alias until the template's methods are
buffered — but that is a direction, not a diagnosis: it has not been measured.

**Corpus effect so far:** `generics.defaults.pas` no longer fails at `:3250`
(`TGOrdinalStringComparer`) at all. Remaining errors there are 6 × `specialize`
and 9 × comparer names (all this ordering defect), plus 5 ×
`SArgumentOutOfRange` — which **does** exist in `lib/rtl/rtlconsts.pas:13`, so
that one is a visibility/export question for **Track B**, not a frontend bug.

**Status:** still unfinished — retitle when picked up; the Delphi ordering
defect is the whole of what is left.

### The enabling fact for the Delphi fix, and the hazard that comes with it

**The whole file is already tokenised when the Delphi specialization runs.**
`LexAll` (`lexer.inc:2618`) fills `Tokens[]` completely before parsing begins —
its own comment says *"the parser has not started"* — and `DelphiRewriteGenericUses`
sweeps that entire stream, so by the time `ParseSpecialization` executes, the
method implementations are **present as tokens** and already rewritten to
`specialize TCmp<T>`. They are merely not yet *buffered* into `GenericMethods[]`.

So the missing prerequisites are not unavailable, only unindexed. That is a much
better position than "defer until the parser gets there", and it means the fix
does not require reordering the parse.

**The hazard, which is why this was not just done:** the obvious move — sweep
raw `Tokens[]` for `specialize X<...>` whose arguments are this template's
parameter names — **over-approximates**. `T` and `U` are the most common
parameter names in existence, so `specialize TCmp<T>` inside a *different*
template's method matches just as well, and would register a prerequisite under
THIS template's substitution: a specialization that is silently wrong rather
than absent. Any fix therefore has to bound the sweep to the token ranges that
are genuinely this template's method implementations.

`GenMethImplSOff` (`defs.inc`) already records the class-name token offset of
every Delphi method-impl header the rewrite touched, which is the beginning of
such a range and the obvious starting point. Finding each range's END is the
part still to work out.

**Do not weaken the prerequisite scan to make the corpus advance.** Registering
a wrong specialization is the failure mode this whole area produces — a plausible
alias built from the wrong substitution — and it would be far harder to see than
the current honest `undefined variable (specialize)`.

## Resolved 2026-08-28 (frankA) — the Delphi ordering defect

The banked diagnosis was right and its one open question turned out to be
already answered in the code.

**What was wrong.** `DelphiRewriteGenericUses` emits its alias declaration right
behind the template declaration, so `ParseSpecialization` runs while
`GenericMethodCount` is still 0. The prerequisite scan swept the class body and
every *buffered* method body — and in mode Delphi there were none yet, so it
reported `nested=0` where objfpc reported `nested=1`, and the literal word
`specialize` survived into the stream.

**The fix.** The scan gains a third source: this template's method impls that the
parser has not reached yet, read straight out of `Tokens[]` (which `LexAll` has
already filled completely) into the template arena as **scratch**, scanned, and
rolled back.

### The open question was not open

The ticket recorded *"`GenMethImplSOff` gives you the start and the end is the
part still to work out."* The end never needed working out: `BufferGenericMethod`
already computes it — scan forward to `begin`, then match `begin`/`case`/`end`
depth. It was inline in that procedure, so it read as part of buffering rather
than as a reusable fact about method extents. Factored out as
`GenericMethodBodyEnd` and now used by both. A second, independently written
range finder would have been the drift this file has already been bitten by.

Same for the copy: `AppendTokenRangeToTemplateArena` is `BufferGenericMethod`'s
own copy loop, shared. And the scan body itself is now
`ScanRangeForNestedSpecs` — one body, three callers (class body, buffered
method, not-yet-buffered Delphi impl), because a second copy per source is
precisely how the method-body arm came to be missing in the first place.

### The hazard was avoided, not braved

The banked warning — **do not weaken the prerequisite scan to make the corpus
advance** — is the reason this is bounded by `GenMethImplSOff`, the class-name
token offsets the rewrite *recorded* when it deleted a `<T>` from a method-impl
header. A range is scanned only when its offset is a recorded header **of this
template**. Attribution is by construction.

The rejected alternative is the one that would have looked simpler: sweep raw
`Tokens[]` for `specialize X<...>` whose arguments match this template's
parameter names. `T` and `U` being the commonest parameter names there are, that
matches inside *other* templates' methods too and registers a prerequisite under
the wrong substitution — a silently wrong specialization, strictly worse than the
honest error it replaces.

**The copy is scratch, and that is load-bearing.** `BufferGenericMethod` keeps
"each (method, specialization) pair is materialised exactly once" via a
before/after split: methods buffered before a specialization go to the pending
queue, ones buffered after are streamed immediately. Registering these scans as
buffered methods would make the parser's own later call the *second* buffering of
the same body, and emit it twice. `TemplateTokenCount` is restored instead.

### Verification

- Repro: FPC prints `8`; pxx now prints `8`. The Delphi trace matches objfpc
  exactly — `SPEC TOrd$Int64$LongInt = TOrd nested=1` → `needs TCmp$Int64`.
- `test_generic_cycle_fail` still correctly **refused**; five other Delphi/generic
  tests named individually still pass.
- **`tools/gate.sh quick`: GREEN**, and it earned its keep — `make
  compiler/pascal26` was green while the **FPC seed build was not**.
  `GenericMethodBodyEnd` is defined below `ParseSpecialization` in the file and
  pxx resolves that either way; FPC does not (`Identifier not found`). Forwards
  added, with the reason in a comment. This is
  `bug-a-fpc-seed-drift-emitasmx64-forward`'s shape, and the per-fix loop alone
  would have pushed it broken.

### Corpus: the wall moved, and the next one is filed

`generics.defaults.pas` no longer fails at `:3231`. It now stops at **`:994`**
with `circular generic specialization` — **earlier in the file, and a truer
error**: before, the prerequisite was silently never discovered at all.

That is **pre-existing and not caused by this fix** — measured by rebuilding this
tree with the change stashed, where the same objfpc repro gives the identical
circular error. Filed as
[[bug-p-mutually-referencing-generics-are-rejected-as-circular]] (p60) with the
real distinction it turns on: `TDel<T> = class(TEq<T>)` is a genuine
declaration-time dependency, while `TEq<T>`'s method body constructing a
`TDel<T>` is materialisation-time, and we treat both as blocking. FPC compiles
it.

## Log
- 2026-08-28 — resolved, commit PENDING-COMMIT.

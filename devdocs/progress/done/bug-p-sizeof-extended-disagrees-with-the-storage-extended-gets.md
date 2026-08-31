---
slug: bug-p-sizeof-extended-disagrees-with-the-storage-extended-gets
track: P
prio: 65
type: bug
blocked-by: []
summary: "The reported bug (SizeOf(Extended) 10 vs storage 8) IS fixed. The MERGE that delivered it REGRESSED and is being corrected by frank-rust -- do not copy the approach from this ticket without reading the 2026-08-31 correction at the bottom. Widening BuiltinTypeNameTk made SizeOf answer for names a USER may declare, and SizeOf consults that table BEFORE the record/alias/array tables, so a user `type Currency = record a,b,c: Integer` answered 8 instead of 12 and a user `var longbool: Boolean` answered 4 instead of 1. The audit finding stands and is real: eight names (ValReal TDateTime Currency Comp LongBool WordBool ByteBool OleVariant) declare fine and were REJECTED by SizeOf(<name>) -- that is bug-p-sizeof-rejects-twelve-type-names-that-a-declaration-accepts [P p40], frank-rust's, filed BEFORE this work with a counter-example. Also corrected here: this ticket's claim that :6417 was the only producer of tyExtended compiler-wide is FALSE (pyparser.inc:46419/:46441)."
status: done
owner: frankwasm
---

# `SizeOf(Extended)` disagrees with the storage `Extended` gets

Found 2026-08-29 while validating a float-residency probe: a local declared
`Extended` was assigned a float resident register, which the residency pass
restricts to `tyDouble`. It was not a residency bug — `Extended` really is
`tyDouble` here — but the type-name table disagrees.

## Measured (2026-08-29, x86-64, `-O2`)

```
                                   pxx        fpc
SizeOf(Extended)=                   10         10
SizeOf(e)      where e: Extended     8         10     <- pxx self-inconsistent
SizeOf(array[1..4] of Extended)     32         40
```

**The FPC column is not the bug.** `Extended` aliasing `Double` is deliberate —
`feature-extended-alias-or-reject`, and `pasparser_lval.inc:6291` says so in
as many words: *"`Extended` aliases Double on every target"*. Answering 8/8/32
throughout would be correct and is what this ticket asks for. The defect is
that **pxx contradicts itself**: 10 from the type name, 8 from a variable of
that type, and 32 for an array of four of them.

## Cause — the same two tables, the same function, the sibling case

`compiler/pasparser_lval.inc` resolves a type name twice:

- **~6295, `BuiltinScalarTypeKind`** — the DECLARATION path.
  `double | extended | valreal | tdatetime | currency` -> `tyDouble`.
- **~6408, the `SizeOf` table** — `else if CaseEqual(nm, 'extended') then
  Result := tyExtended`.

`tyExtended` is ordinal 20 and sizes as the 10-byte x87 type; `tyDouble` is 19
and sizes 8. So the two paths disagree for exactly one type name.

This is the unfixed arm of a double case that was already found and fixed on
its other arm. The comment sitting **six lines above** the offending line
describes the identical failure for `Real`:

> *"`Real` is the target's NATIVE float depth, not an alias for Double ... This
> line used to say tyDouble outright, and since SizeOf consults THIS table and
> declarations consult BuiltinScalarTypeKind, `SizeOf(Real)` answered 8 on those
> targets for a variable that occupied 4."*

CLAUDE.md's rule for this is explicit — *if you fix a bug on one arm of a double
case, grep for the sibling before closing the ticket* — and
`devdocs/dev/normalise-dont-special-case.md` is the argument for why the second
path is the one that stays broken. `Extended` was the sibling and it was not
grepped for.

## Why it is a bug and not a compat item

By the compat table in CLAUDE.md this is the *silent wrong behaviour* escape,
not a parity item: nothing here is about matching FPC. A stride, `GetMem`,
`Move` or `FillChar` size computed from `SizeOf(Extended)` is **two bytes too
long per element** against storage that is genuinely 8, so walking an
`array of Extended` with that stride desynchronises after the first element and
reads into the next. No diagnostic, wrong values, far from the cause.

## Suggested fix

Make the `SizeOf` table agree with the declaration path: at
`pasparser_lval.inc:6408`, `extended` -> `tyDouble`. Then check the rest of that
table against `BuiltinScalarTypeKind` in the same pass rather than one name at a
time — `valreal`, `tdatetime` and `currency` are mapped to `tyDouble` by the
declaration path and should be confirmed, not assumed, on the `SizeOf` side.

Whether `tyExtended` should continue to exist at all once nothing produces it is
a separate question and probably a Track U one: `EmitStoreVar`'s `tk =
tyExtended` arm emits an x87 `fldl`/`fstpt` pair that no declared variable can
currently reach.

## Repro

```pascal
program ext;
var e: Extended; a: array[1..4] of Extended;
begin
  Writeln(SizeOf(Extended), ' ', SizeOf(e), ' ', SizeOf(a));   { 10 8 32 }
end.
```

## Gate

Track P: `make compiler/pascal26` (the self-host fixedpoint) plus this repro
printing three consistent numbers.

## Parked in `float/`, then UN-PARKED the same day — 2026-08-30

Moved `backlog_new/` → `float/` with the rest of the `Extended` cluster, at the
owner's request, so the whole set can be worked in one consolidated session
(umbrella: [[feature-a-extended-is-an-alias-for-double]]).

**Two consequences to be aware of, because they cut against each other:**

1. **This ticket is NOT blocked by the umbrella and should not wait for it.**
   It is a self-inconsistency inside the *current alias*, not a step toward
   80-bit Extended. Confirmed on this tree 2026-08-30: `:6417` is the **only
   site in the whole compiler that produces `tyExtended`** — every other
   reference (`ir_codegen.inc`, the backends, `cparser.inc:133`/`:172`) is a
   consumer firing only on an already-Extended operand. Fixing it makes
   `tyExtended` genuinely dead, which is the cleanest possible starting position
   for the umbrella: both tables then move together, in one place, instead of
   the split having to be re-merged first. It makes the big job smaller.

2. **`float/` is never scanned by `ready`/`next`, so this prio-65 bug is now
   invisible to the ranker.** That is the intended cost of parking, but note
   this ticket is arguably not Track F at all by the folder's own rule — *rank
   the mechanism, never the datatype.* Its subject is a two-table disagreement
   producing a wrong `SizeOf`, and its damage is a stride two bytes too long per
   element walking an `array of Extended`: silent wrong values, far from the
   cause. That is the mechanism, and the `Extended` content is incidental — the
   same defect on the `Real` arm was fixed as an ordinary Track A bug.

   It is parked here because the owner asked for the cluster to be consolidated,
   which is a decision about *attention*, not a reclassification. **If the
   consolidated session does not happen soon, move this one back to `backlog/`
   on its own** — it is a one-line fix at `pasparser_lval.inc:6417` plus the
   audit of the sibling names (`valreal`, `tdatetime`, `currency`) that the
   Suggested fix already asks for, and it does not need the session.

### UN-PARKED 2026-08-30 (owner) — this one is correctness, not float work

> *"for now we treat 'extended' as 'double' across all targets, right? so, this
> makes the sizeof() ticket indeed relevant, as we should not lie. so that is a
> minor fix. that will give us correctness ... so, sizeof() ticket can move back
> to backlog"*

Yes — and confirmed against the source, not assumed. `pasparser_lval.inc:6304`
maps `extended` to `tyDouble` **unconditionally**, with no target test, so
`Extended` is `Double` on every target today including riscv32 and xtensa (where
that `Double` is itself softfloat). Unlike `Real`, which *is* target-dependent
via `RealTypeKind` — that divergence is a separate open question in
[[decide-is-real-a-double-or-fpcs-80-bit-extended]] and is **not** part of this
fix.

So the policy is settled and stable: **`Extended` = `Double`, all targets, for
the foreseeable future.** The rest of the cluster stays parked in `float/` until
it becomes relevant *"or until some mathematician studies the topic and comes up
with a solid plan."*

That makes this ticket the one piece of the cluster that is **not** a float
feature at all. Under a permanent alias, `SizeOf(Extended)` answering 10 against
storage of 8 is simply the compiler **stating something untrue about its own
type** — the owner's phrasing, *"we should not lie"* — and the damage is the
ordinary silent-wrong-values kind: a stride, `GetMem`, `Move` or `FillChar`
sized from it is two bytes too long per element.

Moved `float/` → `backlog/`. This is the F charter working as designed rather
than an exception to it: **rank the mechanism, never the datatype.** The
mechanism is a two-table disagreement producing a wrong constant; the `Extended`
content is incidental, exactly as it was when the same defect on the `Real` arm
was fixed as an ordinary bug.

**Scope, unchanged and small:** `pasparser_lval.inc:6417`, `extended` ->
`tyDouble`, plus the audit the Suggested fix already asks for — check `valreal`,
`tdatetime` and `currency` in that same table against `BuiltinScalarTypeKind`
rather than assuming them. Note this also makes `tyExtended` genuinely dead
(`:6417` is its only producer compiler-wide, measured 2026-08-30), which is the
clean starting position if the cluster is ever revived.

---

## FIXED 2026-08-31 (frankwasm) — and the audit found eight more, so it is a MERGE

Binary `cf1d5398838a` (self-host fixedpoint, `converged after 1 round(s)`).

### The reported bug

`SizeOf(Extended)` 10, `SizeOf(e)` 8. Fixed. All three numbers are now 8/8/32.

### The audit this ticket asked for, and it was not a formality

The Suggested fix said to check `valreal`, `tdatetime` and `currency` against
`BuiltinScalarTypeKind` "rather than assuming them". Done, over all 37 builtin
scalar names, both constructs, against fpc 3.2.2. **Eight names were not merely
mis-sized — the `SizeOf` path REJECTED them outright:**

```
ValReal TDateTime Currency Comp LongBool WordBool ByteBool OleVariant
    var v: <name>   -> compiles, correct width (8 8 8 8 4 2 1 16)
    SizeOf(<name>)  -> "SizeOf: unknown type or variable"
```

So `var v: Currency` worked and `SizeOf(Currency)` did not compile. That is the
same defect as the reported one, one notch further along: not two tables
disagreeing about a width, two tables disagreeing about whether the type exists.

### So the fix is the merge, not the one line

`BuiltinScalarTypeKind` turned out to be a strict SUPERSET of the list
`BuiltinTypeNameTk` kept, and `extended` was the ONLY name where the two
disagreed — this list being the wrong one. Nothing to preserve and no name to
lose, so `BuiltinTypeNameTk` now delegates to it and keeps exactly one genuine
extra: bare `string` -> `BareStringKind` (the declaration site owns its own arm
because it also sets `LastTypeStrCap`, and only side-effect-free names live in
the shared table).

**AFTER: 0 self-inconsistent names of 37**, measured. Nine names changed
behaviour, all in the correcting direction: `Extended` 10 -> 8, and eight
rejections -> correct widths.

The one-line fix at `:6417` would have left the eight rejections in place and
the two tables still two. Fourth fix on the same split, in the same function
(`Real`, bare `string`, `Extended`, and now the eight) — which is
`devdocs/dev/normalise-dont-special-case.md` collecting for the fourth time:
*the second path is the one that stays broken.*

### CORRECTION — `tyExtended` is NOT dead, and this ticket said it would be

Both earlier notes state that `:6417` is *"the only site in the whole compiler
that produces tyExtended"*, so fixing it makes the kind dead. **That is false,
and it would have been acted on:** the ticket proposes deleting `tyExtended` on
the strength of it.

The Pascal frontend no longer produces it. `compiler/pyparser.inc` still does,
twice, from a name and from a token:

```
pyparser.inc:46419   else if CaseEqual(tiName, 'extended') then tiTk := tyExtended;
pyparser.inc:46441   tkExtended_T: tiTk := tyExtended;
```

`cparser.inc:134`/`:172` also yield `Ord(tyExtended)`, though only by
propagating an operand that is already Extended, so those are consumers.

The claim was checked against the Pascal frontend and stated about "the whole
compiler" — the two are not the same scope, and the gap is a whole frontend.
Whether `tyExtended` should exist is still a reasonable Track U question; it is
now a question with **Track N in it**, and it cannot be settled from
`compiler/pasparser_*.inc` alone.

### Not this ticket, found by the same audit, filed separately

`UnicodeChar` is `tyUCS4Char` (4 bytes) here and `WideChar` (2) in FPC. Both pxx
columns AGREE, so it is not a two-table split — it is one table with a
questionable entry, and it needs a decision rather than a correction. See
[[bug-p-unicodechar-is-a-4-byte-code-point-and-fpc-makes-it-a-2-byte-code-unit]].

`Variant`/`OleVariant` are 16 here against FPC's 24, and `string` is a managed
handle against FPC's 256-byte shortstring. Both are deliberate representation
choices, both self-consistent, neither is this.

### Gate

`make compiler/pascal26` (self-host fixedpoint), `tools/gate.sh quick` GREEN,
and `test/test_sizeof_builtin_type_names.pas` wired into `test-core` — it checks
both halves of every affected name and is a positive control: `pinned` REJECTS
it, so it can fail.

## Log
- 2026-08-31 — resolved, commit ce4d9004c.


---

## CORRECTION 2026-08-31 (frankwasm) — the merge above REGRESSED; the audit finding did not

`ce4d9004c` is a wrong-answer regression on master. frank-rust measured it and
owns the fix; this note exists so nobody reads the section above as a recipe.

**Confirmed here on `cf1d5398838a`**, their source, `{$MODE OBJFPC}{$H+}`:

```pascal
type Currency = record a, b, c: Integer; end;
var longbool: Boolean; tdatetime: array[0..9] of Byte;
```

| | fpc | pinned | master after ce4d9004c |
| --- | ---: | ---: | ---: |
| `SizeOf(Currency)` (the USER's record) | 12 | 12 | **8** |
| `SizeOf(longbool)` (a Boolean variable) | 1 | 1 | **4** |
| `SizeOf(tdatetime)` (a 10-byte array) | 10 | 10 | **8** |

**Mechanism.** `SizeOf` consults `BuiltinTypeNameTk` FIRST and only reaches the
record/alias/array tables in its `else`. Widening that table therefore widens
the set of names a builtin can STEAL from the user. The function's own header
says so — *"Callers must consult a user type alias FIRST where that matters"* —
and the merge did not touch a single caller.

### Why the two facts do not cancel

The **audit** is sound and independent of the merge: eight names really do
declare a variable of the correct width and really are rejected by
`SizeOf(<name>)`. That is
[[bug-p-sizeof-rejects-twelve-type-names-that-a-declaration-accepts]] [P p40],
filed by frank-rust BEFORE this work, with a counter-example and a control
program, and its body says in as many words that merging the two bodies is the
tempting move and is not the fix. The bug is real; the merge is not the way to
it.

### The failure worth recording, because it is not "did not read the ticket"

I read the **function header**, which states the hazard outright, and quoted its
neighbourhood in the commit message. I read it as a DESCRIPTION of the
function's contract, not as a PRECONDITION on the change I was making, so it
never became something to test. Prose next to code reads as *what this is*, and
nothing in a header distinguishes that from *what you must not do next*.

The mechanical version generalises further: the accept-side control was 37
names, both constructs, against FPC — and **every one of the 37 was a builtin.**
The change widened WHICH NAMES the table answers for. A control drawn entirely
from the population the change is about cannot detect a change to that
population's BOUNDARY. The one arm that mattered — a user type named `Currency`
— was the one arm not in it. Thorough, in the only direction that could not
fail.

### Coupling, for whoever lands the correction

`ce4d9004c` also wired `test/test_sizeof_builtin_type_names.pas` into
`test-core`, and that test DEPENDS on the merge — it calls ten builtin names
through `SizeOf(<name>)`, which the pre-merge table rejects. A straight revert
of the `pasparser_lval.inc` hunk makes it a hard compile failure. Revert the
wiring and delete the file in the same commit, or keep the merge and fix the
CALLER ordering, in which case the test stands.

---
slug: bug-p-object-value-types-standard-meaning
title: "`object` must mean the standard Pascal value type, not pxx's superseded rooted reference"
track: P
prio: 70
type: bug
blocked-by: []
status: done
owner: frank-user
created: 2026-08-30
summary: "pxx spends the `object` keyword on a rooted class reference — a stopgap from before builtin TObject existed, now redundant with it and used in 4 lines of its own two tests. Real FPC source that declares `= object` (generics.collections.pas, rung 6 of the corpus expansion at p75) therefore fails to compile. Retire the rooted reference (its tests convert to TObject with byte-identical output), and give `object` its standard meaning: a value type lowered as a record with methods, hard-erroring on inheritance/virtual/constructor/destructor."
---

# P: `object` gets its standard meaning; the rooted reference is retired

Decided in `decided/decide-revisit-object-types-rtl-generics-fired-the-trigger`
(owner, 2026-08-30). Filed as a **bug**, not a feature, per CLAUDE.md's compat
table: *real Pascal source compiles wrong, or not at all -> bug, own lane, own
prio*.

## Repro

```
$ pinned generics.collections.pas
pascal26:146: error: generic templates must be class, record, interface,
                     array or procedure declarations
  near:  T  PT   >>> object strict private
```

The blocking declaration is a **stateless methods-only handle** — no fields, no
inheritance, no virtual methods, no constructor, reached by `@` as a pointer:

```pascal
TCustomPointersCollection<T, PT> = object
strict private type
  TLocalEnumerable = TEnumerable<T>;
protected
  function Enumerable: TLocalEnumerable; inline;
public
  function GetEnumerator: TEnumerator<PT>;
end;
```

Exactly **one** `= object` across all six rtl-generics units, with 7 references.

## Part 1 — retire the rooted reference

`pasparser_decl.inc:492` resolves `object` in type-*reference* position to
`tyPointer` with `PtrElemTk=tyClass`, `PtrElemRec=REC_NONE`. It was added
2026-07-03 (`7859911e3`) to provide "a lightweight root, like TObject without a
unit". Builtin `TObject` landed 2026-07-12 (`c53dd8953`,
`RegisterBuiltinTObject`), which supersedes it entirely.

- Remove the `object` arm in `pasparser_decl.inc`.
- Remove the bare-member-access diagnostic in `ParseLValueAST` ("member access
  on a bare object reference; cast to a concrete class first") — the construct
  it guards stops existing.
- `test/test_object_reference.pas` -> substitute `TObject`. **Verified on the
  pinned compiler: byte-identical output and identical code size
  (code=63287B data=4276B bss=42532B).**
- `test/test_object_reference_error.pas` tests the diagnostic being removed —
  repurpose it for the new value-object hard errors (Part 2) rather than delete,
  so the error paths stay covered.

## Part 2 — `object` as a value type

Accept `object` in type-*declaration* position and lower it exactly as a
record-with-methods. The two positions are distinguishable by one token of
lookahead (`var o: object;` ends at `;`/`)`; `type T = object` is followed by
members or an access specifier), but with Part 1 done there is no ambiguity left
to resolve.

Already supported on HEAD and needing no new work — generic records with
methods, `strict private type` sections, pointer-to-specialization access. The
deltas are:

1. the parser arm in type-declaration position;
2. `protected` inside it — records refuse it ("records do not inherit"), and it
   is inert here since nothing derives from the type.

**Hard-error, naming this ticket, on:** an ancestor (`= object(TParent)`),
`virtual`/`dynamic`/`override`, `constructor`/`destructor`. Those are the real
second-object-model cost and are deliberately out of scope. A loud diagnostic is
the whole point — the earlier `decide-old-style-object-types` refused a middle
option specifically for *silently* refusing `virtual`.

## Gate

`make compiler/pascal26` (self-host fixedpoint) + the repros:
- `generics.collections.pas` gets past line 146;
- converted `test_object_reference.pas` still prints the 7 expected lines;
- each hard-error case produces its diagnostic, not a wrong program.

Breadth is Track T's against the pushed sha.

## Consequences

- Unblocks rung 6 of [[feature-pascal-corpus-expansion]] (p75).
- [[feature-p-legacy-value-object-types]] (p15) assumes option B's full scope —
  rewrite to this scope or close in favour of this ticket.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.

## Resolution (2026-08-30)

Both parts landed. `object` in type-DECLARATION position is now the standard
Pascal value type with methods, lowered as an advanced record; the rooted
class reference it used to mean in type-REFERENCE position is gone.

**Part 1** removed the `object` arm in `pasparser_decl.inc` and converted
`test_object_reference.pas` to `TObject`.

Two corrections to what Part 1's own commit message claimed, both worth
recording because both were the same mistake — asserting rather than measuring:

- **`object` and `TObject` were NOT the same internal type.** The byte-identical
  output that "proved" it came from a test using only casts and assignment,
  where both representations are a pointer move; it could not discriminate.
  `RegisterBuiltinTObject` mints a real class row, so `var o: TObject` takes
  ordinary class member lookup, while the `pasparser_decl.inc:692` tyPointer arm
  is only a fallback for when no such row exists.
- **The bare-object diagnostic was KEPT, not removed** as this ticket's Part 1
  section said to. It is not object-specific — it fires for any
  tyPointer/tyClass/REC_NONE, which is also what `TClass` lowers to — and
  fpcunit depends on the class-reference operations it permits. So
  `test_object_reference_error.pas` was repointed at `TClass` rather than
  repurposed for the Part 2 errors, which got their own three files.
  Track T on `seven` caught the gap between the ticket and the commit
  (`regression-test-core-test-object-reference`, NEW-RED at f9bfcca97409).

**Part 2** added the type-declaration arm, `protected` under `object`, generic
`object` templates, and the three refusals — ancestor, virtual/dynamic/override/
abstract, constructor/destructor — each naming this ticket. Two of the three had
to be explicit rather than merely absent: the record machinery underneath would
have *accepted* `constructor` silently, and `virtual` falls out of the record
directive loop to be misread as the next field. `isObjectType` is threaded as a
parameter, not a global, so nothing in `defs.inc` changed and no Track A ticket
was needed.

**The repro, measured both ways against the same file:**

```
pinned:  generics.collections.pas:146: error: generic templates must be class,
         record, interface, array or procedure declarations
HEAD:    past it; the wall moves to :120, `unknown type: PT`
```

The new wall is a pre-existing generics scope gap that `pinned` never reached,
because it aborted 26 lines *later* at the syntax error before any
specialization was streamed. Filed as
[[bug-p-generic-type-param-unresolved-in-class-abstract-template]] (p70), which
is now what rung 6 of [[feature-pascal-corpus-expansion]] waits on.

**Follow-ups not done here:**

- The record arm still handles `virtual` by falling out of the directive loop.
  Deliberately unchanged — the same clear diagnostic would fit, but it is a
  different lane's risk and belongs in its own ticket.
- [[feature-p-legacy-value-object-types]] (p15) assumes the full old-style
  object model, which this ticket deliberately refuses. Close it in favour of
  this one, or rewrite it as "give `object` a VMT", which is a real and
  much larger decision.

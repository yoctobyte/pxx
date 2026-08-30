---
slug: bug-p-object-value-types-standard-meaning
title: "`object` must mean the standard Pascal value type, not pxx's superseded rooted reference"
track: P
prio: 70
type: bug
blocked-by: []
status: working
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

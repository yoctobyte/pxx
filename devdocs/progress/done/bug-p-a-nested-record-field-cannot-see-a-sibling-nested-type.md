---
track: P
prio: 60
type: bug
status: done
blocked-by: []
owner: frankO
summary: "A type nested in a class was invisible to a nested RECORD's field declaration in the same section -- `TVMT = record __ClassRef: TFacClass; end` inside a class could not see the `TFacClass` declared two lines above it. Green on pin fe1e9c37d322, broken by c01eb17a8, bisected over 63 commits. It blocked corpus rung 6a (generics.defaults), which had been RECORDED GREEN and never re-run. Cause: parsing a nested type's body retargets ParsingClassBodyCi at that nested type, so for exactly the span of the nested record's field list the enclosing class stopped being the value AliasVisibleHere compared against. Fixed by making the lexical chain explicit (UClsEnclosingCi, written where the two body parsers already save the previous value) and walking it, which COLLAPSES arms 1 and 2 rather than adding a fifth. Arms 3 and 4 deliberately left as exact comparisons -- they are not chain positions."
---

# A nested record's field cannot see a sibling nested type

```pascal
type
  TFac = class
  public type
    TFacClass = class of TFac;
    TVMT = record __ClassRef: TFacClass; end;   { error: unknown type: TFacClass }
  end;
```

Declared two lines above, same section. Not a forward reference.

## Boundary, varied rather than assumed

| shape | pin v404 | HEAD before fix |
| --- | --- | --- |
| nested type used by a nested **record field** | ok | **unknown type** |
| same, plain alias instead of `class of` | ok | **unknown type** |
| the same two declarations at **unit level** | ok | ok |
| nested type used by a nested **pointer** | ok | ok |

The pointer arm working is why this read as already fixed.

## Cause

`AliasVisibleHere` was four arms: `owner < 0`, `= ParsingClassBodyCi`,
`= MethImplOwnerCi`, `= QualTypeOwnerCi`. Parsing a nested type's body does
`savedPCB := ParsingClassBodyCi; ParsingClassBodyCi := ci`
(`pasparser_decl.inc`, both body parsers), so within the nested record's field
list the enclosing class is no longer that variable's value.

**The arm count had gone 2 → 3 → 4, each added by a session with a failing test
and no way to see the ranges it was not testing**, and this would have been the
fifth. frankB's statement of why that never terminates is worth keeping: *"an
enumerated predicate makes the arms you HAVE visible and says nothing about the
ranges nobody has tested — so it reads as a census while being a log of what has
broken so far."*

## Fix

The nesting chain existed only as `savedPCB` locals on the parser's call stack —
nowhere addressable, so every consumer re-derived it from whichever single
variable was in scope. `UClsEnclosingCi` writes it down at the two points the
body parsers already have the enclosing ci in hand, and `AliasOwnsThrough` walks
it. That **collapses arms 1 and 2**, which were both approximations of "somewhere
in the enclosing chain".

**Arms 3 and 4 stay exact comparisons, deliberately, and I wrote it the wrong way
first.** An out-of-line method body is not lexically inside anything, and
`QualTypeOwnerCi` is — frankB's words — *"a lookup being told which owner to
answer for"*: `FindNestedClassLikeCi` sets it around a `FindTypeAlias` call while
walking an ancestor chain, from outside any lexical nesting. Walking a chain from
either answers a different question than the caller asked.

## Provenance and verification

Bisected over the 63 commits in `5b5fdb0b3` (pin v404) `..de4bf2245`, six builds,
each seeded from the pin with the `touch` after the `cp`, each accepted only on
`converged after` **and** a built sha differing from the seed. `60666ec36` good,
`c01eb17a8` bad.

Census 1876 files, **0 rows differ** against a baseline rebuilt at the same tree
— re-taken because the first comparison was contaminated: `sync.sh` had rebased
other agents' commits in between the two arms, including one that added two test
files, so the file count moved and the diff was not about my change.
Conformance 384 pass / 1 fail and fgl 7/7, both unchanged.

`test/test_nested_alias_visible_through_enclosing_chain.pas` has five rows, and
**row 3 is depth 2** — a record inside a record inside the class, naming a type
owned by the outermost. A fifth arm comparing against "the enclosing class"
passes row 1 and fails row 3, so that row is what distinguishes the rule from one
more special case. Row 4 keeps the pointer spelling so a future fix cannot repair
fields by breaking pointers. Controls: the pin prints `NESTEDCHAIN OK` (the
behaviour existed and was lost), and the pre-fix binary refuses to compile it.

## What it unblocked, and what it did not

Corpus rung 6a (`generics.defaults`) advances from `:1107 unknown type:
PSpoofInterfacedTypeSizeObject` to `:1865`. It is **still red**, on a second and
unrelated regression in the same window: a class method reached through a
class-REFERENCE field is parsed as a FIELD READ. The statement spelling errors
with `statement is neither a call nor an assignment`; the EXPRESSION spelling
**compiles and silently yields garbage** — `r := PP(p)^.__ClassRef.Val(3)`
printed `r=-86205216` with the method never entered, where fpc 3.2.2 and pin
v404 both print `SIDE called n=3` and 42. The pin is correct, so it is a
regression too, and it is not this one. Reproducer, measured cause (the parser
returns `AN_FIELD` with the `(` unconsumed) and a bisect recipe are in
`bug-p-a-class-method-through-a-class-ref-field-is-parsed-as-a-field-read`.

**The ladder had recorded rung 6a green and nobody re-ran it** — the file's own
standing lesson, which is why the first thing this session did with the ticket
was re-run the rung rather than read the table.

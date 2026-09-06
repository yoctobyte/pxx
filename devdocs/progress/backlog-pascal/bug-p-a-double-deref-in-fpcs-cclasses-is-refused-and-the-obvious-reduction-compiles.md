---
slug: bug-p-a-double-deref-in-fpcs-cclasses-is-refused-and-the-obvious-reduction-compiles
title: "`cclasses.pas:2909` — `Entry := @Entry^^.Next` refused with `dereferenced value is not a pointer`, and the obvious reduction COMPILES"
track: P
prio: 45
type: bug
status: backlog
owner: ""
created: 2026-09-05
found-by: frankB
blocked-by: []
summary: "The current wall on the FPC compiler-source march, and the first one this session that did NOT reduce. `cclasses` / `comphook` / `finput` / `cfileutl` stop at `cclasses.pas:2909 dereferenced value is not a pointer` — `Entry := @Entry^^.Next` inside `THashSet.Lookup`, where `Entry: PPHashSetItem` and the three types are declared forward (`PPHashSetItem = ^PHashSetItem` above `PHashSetItem = ^THashSetItem` above the record). A hand-written reduction with those exact declarations, that exact routine body and a class field of the same type COMPILES AND RUNS, so the discriminator is something else in the unit and the reduction is the work. Two separate small shapes DO fail and are recorded below; neither produces this diagnostic, so neither is established as the cause."
---

# The wall

```pascal
type
  PPHashSetItem = ^PHashSetItem;        { cclasses.pas:486 }
  PHashSetItem  = ^THashSetItem;        { :487 }
  THashSetItem  = record
    Next: PHashSetItem; Key: Pointer; KeyLength: Integer;
    HashValue: LongWord; Data: TObject;
  end;
...
  Entry := @FBucket[h and (FBucketCount-1)];
  while Assigned(Entry^) and
    not ((Entry^^.HashValue = h) and (Entry^^.KeyLength = KeyLen) and
      (CompareByte(Entry^^.Key^, Key^, KeyLen) = 0)) do
        Entry := @Entry^^.Next;         { :2909 — refused }
```

Measured under `--mimic-fpc-compiler` against `/usr/share/fpcsrc/3.2.2/compiler`
with compiler `7c76da7cf0fa`.

# What does NOT reproduce it, which is the useful half

A program with those three declarations verbatim, a `THashSet = class` carrying
`FBucket: PPHashSetItem`, and a `Lookup` whose body is the loop above (minus
`CompareByte`) **compiles and runs**. So none of these is the discriminator on
its own: the forward pointer-to-pointer chain, the self-referential record, the
class field of PP type, `@FBucket[i]` indexing a pointer, `Assigned(Entry^)`,
`Entry^^.field`, or `Entry := @Entry^^.Next`.

That is worth stating plainly because it is where a reader would start, and it
is a dead end. The remaining candidates are things the reduction dropped: the
`CompareByte(Entry^^.Key^, ...)` term, `TSymStr`/`symansistr` conditionals in
force under `--mimic-fpc-compiler`, or interference from a declaration earlier
in a 3000-line unit.

# Two neighbouring shapes that DO fail

Found while probing, both real, neither producing this diagnostic:

```pascal
type PPI = ^PI; PI = ^TI; TI = record hv: LongWord; nx: PI; end;
var b: PPI;
  writeln(b[0]^.hv);   { "hv": a pointer has no members (dereference it with ^,
                         or the pointee type is unknown here) }
```
`b[0]^` — indexing a pointer-to-pointer and then dereferencing the element.
`@b[0]` followed by `e^^` works, so the element's pointee is knowable and this
spelling does not ask for it.

# Do not confuse this with

[[bug-p-a-forward-pointer-to-a-named-array-type-loses-its-element]], which was
the PREVIOUS wall on this march (`cclasses.pas:1274`) and is fixed. Three walls
fell in one session — `TFPCHeapStatus`, the forward pointer-to-array, and
`Prefetch` — each visible only once the one in front of it was gone. This is the
fourth and it is the first that did not yield to a reduction.

## 2026-09-06 (frankS) — the "two neighbouring shapes that DO fail" section is stale

Both now compile and run, measured at `d712038df` with compiler `1c3ab9613b2e`:

- `Entry := @Entry^^.Next` with the forward `PPHashSetItem`/`PHashSetItem`/record
  chain and the loop body — compiles, prints the field.
- `b[0]^.hv`, recorded here as `"hv": a pointer has no members` — compiles,
  prints 7.

This is **not** a claim that the `cclasses.pas:2909` wall moved. The ticket is
explicit that neither shape produced that diagnostic and neither was established
as the cause, so their passing says nothing about the wall itself — it only
retires them as candidates and as starting points for the next reader.

The wall needs a driver under `--mimic-fpc-compiler` against
`/usr/share/fpcsrc/3.2.2/compiler`, and there is no committed harness — the march
is driven by hand. Not attempted here for the reason frankB banked on 2026-09-05
after retracting two march findings: *"a substitute for a flag is a configuration
nobody else runs, so every number it produces is unshared."* This wants whoever
holds the march configuration.

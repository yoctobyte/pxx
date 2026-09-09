---
slug: bug-p-a-double-deref-in-fpcs-cclasses-is-refused-and-the-obvious-reduction-compiles
title: "`cclasses.pas:2909` — `Entry := @Entry^^.Next` refused with `dereferenced value is not a pointer`, and the obvious reduction COMPILES"
track: P
prio: 45
type: bug
status: done
owner: frankH
created: 2026-09-05
found-by: frankB
blocked-by: []
summary: "GONE, and attributed. `cclasses.pas:2909` compiles at master tip and at pin v407, in the ticket's own configuration (`--mimic-fpc-compiler -Fu/usr/share/fpcsrc/3.2.2/compiler`): `uses cclasses` builds and the program runs. Bisected to `a4cbaa1de` (2026-09-06), which made `ResolvePendingPointerAliases` a bounded fixedpoint instead of one forward pass — that commit's own message records pin v404 refusing its three-level row with THIS diagnostic, so the two are the same defect reached from two directions. Its `test_forward_double_pointer_alias_order.pas` is the guard; this ticket cannot add one, because its own reduction never failed. The march's frontier is now `cfileutl.pas:136 unknown type: TExecuteFlags`."
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

## 2026-09-09 (frankH) — closed: the wall is gone, and the bisect names why

Measured at master `3188b5c38`, compiler `cea180134ee7` (`converged after 2
round(s)`; stamp removed first so nothing could answer from another tree's):

```
$ pascal26 --mimic-fpc-compiler -Fu/usr/share/fpcsrc/3.2.2/compiler cc.pas
ok: cc  [code=532248B ...]
$ ./cc
cc ok
```

where `cc.pas` is `program cc; uses cclasses; begin WriteLn('cc ok') end.` —
the ticket's configuration exactly, no extra `-Fu`.

Controls, because "it compiles now" has three boring explanations:

- **The source is unchanged.** `Entry := @Entry^^.Next;` is still at `:2909`,
  `cclasses.pas` md5 `1945fdf0a8098c40e189cb830792a9b9`.
- **The flag is live.** `--mimic-fpc` without `-compiler` fails differently
  (`globtype.pas:110 unknown type: PInt`), so the mimic mode is being entered.
- **It is not this session's delta.** It compiles at pin v407 (`51901941e`) too.

### Attributed: `a4cbaa1de`, 2026-09-06

`git bisect` with `--term-old=broken --term-new=fixed`, `broken cf7101dfa`
(2026-09-05) → `fixed 51901941e`, ~10 build steps, each one `rm -f
compiler/.pascal26.fixedpoint` then `make compiler/pascal26` (exit 125 on a
build failure so a tree that cannot build is skipped rather than voted):

```
a4cbaa1dee1cd6b450f0a1d4807e47cd2002aae8 is the first fixed commit
    fix(P): the forward-pointee alias repair ran ONCE, forward — order decided the answer
```

`ResolvePendingPointerAliases` walked the alias table once in index order, so a
pointer-to-pointer row declared ABOVE its pointee copied a base still at
`REC_NONE` and nothing revisited it. `cclasses` spells its chain in exactly that
order (`PPHashSetItem` at `:486`, `PHashSetItem` at `:487`). That commit's own
message records `pin v404 refuses the three-level row outright with
"dereferenced value is not a pointer"` — the same diagnostic this ticket is
named for. It was found and fixed from the reduction side while this ticket held
the corpus side; neither knew about the other.

### Why the bisect predicate was "does cclasses compile AT ALL"

Not "does the `:2909` message appear". At the oldest in-range commit
`cf7101dfa` the wall is `cclasses.pas:676 unknown type: TFPCHeapStatus` — walls
fall in SEQUENCE in this unit, so a predicate keyed on the message answers
"fixed" for every commit whose parse stops EARLIER, which is the wrong
direction and reads as a clean bisect. Same inversion as
[[bug-p-the-generics-corpus-wall-moved-backward-from-2729-to-224]], rejected
this morning: **a stopping point that moves is not the same observable as a
declaration that fails.**

### No regression fixture from this ticket, and that is not a gap

The ticket's own reduction — the three forward declarations, the class field of
`PP` type, the `Lookup` body — **compiled throughout**, on the day it was filed
and today. A shape that never failed cannot guard anything. The guard already
exists and is already wired:
`test/test_forward_double_pointer_alias_order.pas`, landed by `a4cbaa1de`,
asserts both fields (`.a` is at offset 0 and is green while the bug is live),
both declaration orders, and a three-level chain. Adding a `uses cclasses` row
would be a 3000-line fixture over a file outside the repo, guarding a defect
that already has a 44-line one.

### The frontier moved to `cfileutl.pas:136`

```
pascal26:136: error: unknown type: TExecuteFlags
  in: /usr/share/fpcsrc/3.2.2/compiler/cfileutl.pas
```

(with `-Fu.../compiler/x86_64` added, or `cpuinfo` is not found first). This is
**not** a parser bug: `TExecuteFlags` is an FPC `sysutils` type and pxx's RTL
does not declare it anywhere — `grep -rn TExecuteFlags lib/rtl/ compiler/builtin/`
is empty. The default-set-after-an-open-array shape parses fine on its own
(probe: two overloads, `F: TEF = []`, plain and `array of AnsiString`, compiles
and prints `1 2`). Filed separately.

**And `tail -4` manufactured a finding here, for the third time today.** The
truncated output showed only the `:137` error, so `:136` — the same type, the
same line, one overload up — looked ACCEPTED, and "the plain-AnsiString arm
resolves it while the open-array arm does not" is a specific, plausible, wrong
diagnosis. `head -20` shows both errors. The instrument did not error; it
answered about the tail.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 6ae25b5f8.
- 2026-09-09 — **the FIX is `a4cbaa1de`** (2026-09-06, `fix(P): the forward-pointee alias repair ran ONCE, forward`), found by bisect. The `PENDING-COMMIT` line above carries only the CLOSE, which changed no compiler code.

---
track: A
prio: 55
type: bug
blocked-by: []
summary: "The duplicate-class-name check added 2026-07-30 uses a FLAT per-unit namespace, so a nested class name that is legally reused in a different enclosing class — or materialized once per specialization of an outer generic — is rejected as a redeclaration. Legal Pascal fails to compile. Two FPC-conformance tests fail on it (tclass13b, tgeneric72); found by Track T while enrolling the battery in the watcher."
---

# `duplicate class name` is scope-blind: nested classes collide across enclosing scopes

- **Type:** bug (duplicate-declaration detection) — **Track A**
- **Status:** backlog
- **Opened:** 2026-08-14
- **Filed by:** Track T, from `task-t-enroll-pascal-conformance-tier`. T owns the
  tool, never the bug — this is the owning lane's.
- **Introduced:** `1c24510b3` *"fix(pascal): a duplicate class name in one unit is
  an error — and pylib had one"* (2026-07-30), **4480 commits ago**.

**Why A and not P.** The check is in the shared `compiler/parser.inc` (~26601),
and `1c24510b3` had to touch `compiler/pyparser.inc` in the same breath to stop
NilPy classes reading as redeclarations of their own stubs — so this is shared
duplicate-declaration machinery serving two frontends, not Pascal-dialect
syntax. Same call, and the same day, as
[[compat-pascal-strict-fpc-should-reject-a-duplicate-identifier-in-one-scope]], which
routed *duplicate-identifier* detection to A for exactly this reason. That
ticket is this one's mirror image and the pair is worth reading together:
it is pxx being too **lax** where FPC rejects (and is therefore `compat`,
behind `--strict-fpc`); this is pxx being too **strict** where FPC accepts,
which makes it a plain bug — legal Pascal that will not compile.

## What

The check rejects a class name that is already declared *anywhere in the unit*,
with no regard for the scope that declares it. Object Pascal nests types inside
classes, so the same identifier legally names different types in different
enclosing scopes — and a generic's nested types are re-materialized once per
specialization, which the flat namespace also reads as a redeclaration.

Both arms, reduced from the failing conformance tests:

**Arm 1 — same nested name under two different outer classes** (10 lines):

```pascal
program rep1;
{$mode delphi}
type
  touter = class
    type tinner = class end;
  end;
  tother = class
    type tinner = class end;   { <-- rejected }
  end;
begin
end.
```

```
pascal26:8: error: duplicate class name tinner — one of that name is already
declared in this unit, and every use of the name binds to the FIRST declaration
```

`touter.tinner` and `tother.tinner` are distinct types with distinct qualified
names. Nothing here is ambiguous to a reader or to FPC.

**Arm 2 — a nested specialization alias, once per outer specialization:**

```pascal
program rep4;
{$mode objfpc}
type
  generic TUsed<T> = class
  var f: T;
  end;
  generic TBox<T> = class
  type
    TItem = record Field: T; end;
    TMyUsed = specialize TUsed<TItem>;   { <-- rejected on the 2nd specialization }
  var
    f: TMyUsed;
  end;
var
  a: specialize TBox<LongInt>;
  b: specialize TBox<Pointer>;
begin
  a := nil; b := nil;
end.
```

`TBox<LongInt>.TMyUsed` and `TBox<Pointer>.TMyUsed` are *supposed* to be two
different classes — that is precisely what `tgeneric72.pp`'s header comment says
it is testing ("that the two specializations of TUsedGeneric ... are unique").
The check counts the second materialization as a duplicate of the first.

## What is NOT broken

Worth recording, because it narrows the fix and rules out the obvious guess.
The commit that added the check explicitly handled forward stubs, and that
handling **works** — a nested forward filled by its full declaration compiles:

```pascal
tc = class
  type
    tforward = class;
    tforward = class end;   { ok — UClsForward is honoured }
end.
```

So this is not the forward-stub path. It is the namespace the check consults.

## Root cause, as far as Track T took it

`FindUClass`-style lookup over a flat per-unit class table (the same flatness
[[bug-p-scope-hiding-covers-routines-but-not-types-and-classes]] describes one
level up, for `uses`-order resolution). The duplicate test asks "is this name
taken in the unit?" when the question is "is it taken **in this declaring
scope**?" — for a nested type the scope is the enclosing class, and for a
generic's nested type it is the enclosing *specialization*.

Per `devdocs/dev/normalise-dont-special-case.md`, the sibling to grep before
closing: the same flat table is what makes the two arms above one bug rather
than two, and a fix that special-cases nesting without also keying on the
specialization instance will fix `tclass13b` and leave `tgeneric72` red.

## How it stayed invisible for 4480 commits

The FPC conformance battery is enrolled in no tier — it runs only when a human
types it, which is the gap `task-t-enroll-pascal-conformance-tier` exists to
close. The battery was recorded at **0 fail** at its burn-down; it is at 2 fail
today, and nothing observed the transition. This ticket is the first thing the
enrolment found.

## Reproduce

```sh
tools/run_pascal_conformance.sh ./compiler/pascal26 \
  library_candidates/fpc-testsuite/tests/test --only 'tclass13b.pp' --all
tools/run_pascal_conformance.sh ./compiler/pascal26 \
  library_candidates/fpc-testsuite/tests/test --only 'tgeneric72.pp' --all
```

Note the compiler path must be one whose directory has `builtin/` beside it and
`lib/` above it — the runner compiles from inside the suite directory, so a bare
`./compiler/pascal26` relative path does not survive its `cd`.

## Gate

`make test` + self-host fixedpoint (byte-identical), plus both conformance tests
above passing without a `pxx.skip` entry. The check's original purpose must
survive: `test_object_ref_array_identity.pas` and the pylib duplicate the commit
found must still be caught.

## If this will not be fixed soon

Track T's enrolment leaves shards 2 and 3 of `test-pascal-conformance` red, and
**a red shard cannot report a further regression** — the other ~90 programs in
each shard lose their NEW-RED signal until this clears. If the fix is not near,
skip-listing these two in `test/pascal-conformance/pxx.skip` with a reference to
this ticket restores that signal. That file is the owning lane's to edit, not
T's, which is why this is a note rather than a commit.

Related: [[task-t-enroll-pascal-conformance-tier]],
[[bug-p-scope-hiding-covers-routines-but-not-types-and-classes]].

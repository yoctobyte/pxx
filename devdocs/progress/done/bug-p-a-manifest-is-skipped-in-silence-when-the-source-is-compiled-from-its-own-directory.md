---
slug: bug-p-a-manifest-is-skipped-in-silence-when-the-source-is-compiled-from-its-own-directory
title: "A pxxlib.cfg is skipped in SILENCE when the source is compiled from its own directory"
track: P
prio: 30
type: bug
status: done
owner: ""
blocked-by: []
summary: "FIXED 2026-09-09 as a DIAGNOSTIC, exactly as filed -- the scoping rule is untouched. `PxxLibFindManifest` walks up from the unit's own directory and deliberately stops before the cwd, and exits immediately on an empty dir, so a source reached as a BARE FILENAME has dir='' and gets no manifest: the same unit resolves its unitalias rows when named by a path and does not when compiled from its own directory, with the ordinary `uses: unit source not found` as the only symptom. A `uses` of a DOTTED name that fails to resolve now adds a note when a pxxlib.cfg sits in the invocation directory unread. NOTE THE REPRO IS NARROWER THAN THE TICKET IMPLIED: a manifest never applies to the main PROGRAM in any invocation (that is the documented per-library scope, not this bug), so the defect needs a UNIT reached by bare filename -- two wrong repros were built before that landed."
---

# A pxxlib.cfg is skipped in silence when the source is compiled from its own directory

- **Type:** bug (diagnostic gap, not a resolution gap)
- **Track:** P — `compiler/paslexer.inc`, `compiler/pasparser_proc.inc`
- **Found:** 2026-09-06, measuring [[feature-embed-dwscript-core]]'s wall ladder

## Repro

With `Source/pxxlib.cfg` carrying `unitalias System.Classes=classes`:

```
cd Source && pxx --mimic-fpc -Mdelphi p.pas out    # unit source not found: system.classes
cd ..     && pxx --mimic-fpc -Mdelphi -FuSource p.pas out   # resolves
```

## Why it reads as a broken feature rather than a mis-invocation

Both the skip and a genuinely absent unit produce the same message, so the
natural next step is to doubt the feature. The discriminator that actually
works is the feature's own positive control (`make`'s `test_libmanifest` row,
which passes) — i.e. you have to already suspect the invocation.

This is the repo's own "every instrument that lies, lies by being correct about
something else": the resolver is correct that `system.classes` is not a unit it
can find, and says nothing about the table it never consulted.

## Not to be fixed by widening the walk

`defs.inc:6578` and `paslexer.inc:398` both state the reason the walk stops
before the cwd. Adding the cwd back would reintroduce exactly the hazard those
notes describe. **Fix the silence.**

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 102d95440.

## 2026-09-09 — fixed as a diagnostic; and the repro is narrower than filed

The prescription was followed exactly: **a note, not a behaviour change.**
Widening the walk to the cwd would reintroduce the hazard the rule exists to
stop, and both `paslexer.inc` and the `defs.inc` design note argue it well.

### Two wrong repros first, and the reason is worth keeping

The ticket's repro compiles `p.pas`, which reads as "the program loses its
manifest". It does not — **a manifest never reaches the main program, in any
invocation.** Measured three ways, all printing `manifest NOT reached`: from the
parent as `Source/p.pas`, from `Source/` as a bare `p.pas`, and from the parent
by ABSOLUTE path. That is the documented per-library scope (`defs.inc`: *"the
scope follows the unit BEING COMPILED"*), and `test_libmanifest`'s own expected
output already says `prog: NO-manifest progdef`.

So the defect needs a **unit** reached by a bare filename. With one:

```
Source/pxxlib.cfg   unitalias My.Lib=mylib
Source/mylib.pas    unit mylib;  procedure Hello;
Source/inner.pas    unit inner;  uses My.Lib;
Source/p.pas        program p;   uses inner;

cd parent  &&  pxx -Mdelphi -FuSource Source/p.pas   ->  compiles, prints MYLIB OK
cd Source  &&  pxx -Mdelphi p.pas                    ->  uses: unit source not found: my.lib
```

Same tree, same files, same flags. `inner` is reached as a bare `inner.pas`, so
`GetFilePath` gives `''`, `PxxLibFindManifest` exits on `Length(dir) = 0`, and
the alias table is never read.

### The note, and what it is NOT allowed to do

Fires only when the unresolved name is DOTTED *and* a `pxxlib.cfg` exists in the
invocation directory. Both halves matter, and both were controlled:

| case | note |
| --- | --- |
| bare filename, dotted name, cfg in cwd | **fires** |
| same file, path-qualified from the repo root | silent |
| dotted name, no cfg in cwd | silent |
| cfg in cwd, name NOT dotted | silent |

The committed pair is the strongest part: `test/libmanifest/unitalias_no_row.pas`
compiled **twice** — path-qualified from the repo root and bare from inside its
own directory — and the note must appear in exactly one. A note that fired in
both would be noise; one that fired in neither is the bug returning.

### Measured

Commit `ae1ce9232` + this change, binary `bfb8de3f14dc`, `converged after 1
round(s)`. `gate.sh quick` GREEN read from the log, FPC seed canary PASS.

### Residual, named rather than left implied

The sibling site `ConcatThree('uses: unit source not found: ', basePath, ...)`
(the C `#include` of a Pascal unit) carries no note. It is reachable by the same
mechanism and was left alone deliberately: the ticket is about `uses`, and a
second diagnostic wants its own control rather than being assumed to work.

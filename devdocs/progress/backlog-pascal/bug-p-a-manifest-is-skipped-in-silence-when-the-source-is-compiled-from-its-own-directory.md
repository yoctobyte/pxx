---
slug: bug-p-a-manifest-is-skipped-in-silence-when-the-source-is-compiled-from-its-own-directory
title: "A pxxlib.cfg is skipped in SILENCE when the source is compiled from its own directory"
track: P
prio: 30
type: bug
status: backlog
owner: ""
blocked-by: []
summary: "MEASURED 2026-09-06 at 8b55d1918, compiler 5ca36ce7aae9. `PxxLibFindManifest` walks UP from the unit's own directory and deliberately stops before the cwd (paslexer.inc:394-403: 'a manifest is a property of where the SOURCE lives'), and it exits immediately on an empty dir. A source given as a BARE FILENAME therefore has dir='' and gets no manifest at all -- so `cd Source && pxx --mimic-fpc p.pas` resolves NO unitalias rows while `pxx --mimic-fpc -FuSource p.pas` from the parent resolves all of them. Same tree, same files, same flags, different answer, and the only symptom is the ordinary `uses: unit source not found: system.classes` a genuinely missing unit produces. THE SCOPING RULE IS NOT THE DEFECT AND SHOULD NOT BE CHANGED -- it is what stops a stray cfg in an invocation directory redefining somebody's build, and defs.inc:6578 argues it well. The defect is that the skip is UNOBSERVABLE: this cost a session an hour of believing the landed unitalias feature was broken, and the wrong conclusion was only caught by running the feature's own test/libmanifest positive control, which passed. SUGGESTED FIX IS A DIAGNOSTIC, NOT A BEHAVIOUR CHANGE: when a `uses` of a DOTTED name fails to resolve and a pxxlib.cfg exists in the failing source's directory but was not consulted, add a note saying so. Cheap, and it fires exactly in the case that is confusing."
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

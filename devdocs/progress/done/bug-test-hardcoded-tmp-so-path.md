---
prio: 40
---

# bug: test_c_lazycasing.pas hardcodes /tmp/liblazycasing.so (non-hermetic test)

- **Type:** bug (test hygiene) — **Track C (C frontend)**
- **Filed by:** the Track T watcher agent
- **Found:** 2026-07-12, while fixing testmgr's private-scratch rewrite

## Problem

`test/test_c_lazycasing.pas:7` bakes an absolute path into the binary:

```pascal
function add_two(a, b: Integer): Integer; cdecl; external '/tmp/liblazycasing.so';
```

Every other C-interop test names the library by soname and lets the loader find
it — `test/test_c_argspill.pas` is the model:

```pascal
function sum7(a,b,c,d,e,f,g: Integer): Integer; cdecl; external 'libspill.so';
```

with the recipe supplying `LD_LIBRARY_PATH` (Makefile:1737).

The absolute path is incidental to what the test is *for* (a9251ffb: the
`{$LAZYCASING ON/OFF}` case-insensitive fallback for C imports). It just means
the test can only ever work if that exact global path exists.

## Why Track T cares

testmgr runs every job in a private scratch dir so two runs on one box (dev
gate + watcher clone) can't clobber each other. A pinned `/tmp` path defeats
that: the .so has to keep being written to the shared global path, so this one
job stays exposed to cross-run races that every other job is now immune to.
testmgr works around it today (`pinned_tmp_paths()` in tools/testmgr.py reads
the job's sources and leaves hardcoded literals alone) — that workaround exists
solely for this one line and can be deleted once it's gone.

## Fix

```pascal
function add_two(a, b: Integer): Integer; cdecl; external 'liblazycasing.so';
```

The recipe (Makefile:1740) already sets `LD_LIBRARY_PATH`, so nothing else
changes. If absolute-path externals are worth covering as a *feature*, cover
them in a test that builds the .so somewhere it owns, not in a shared /tmp.

## Gate

`tools/testmgr.py --tier native --job 'test-core#554'` green on a box with a
clean /tmp (`rm -f /tmp/liblazycasing.so` first — a stale copy from an old
serial `make` masks the whole problem), and no /tmp artifacts left behind.

## 2026-07-14 — RESOLVED (b368)

`test_c_lazycasing.pas` now names the library by soname
(`external 'liblazycasing.so'`), exactly like test_c_argspill; the Makefile
recipe already runs it with `LD_LIBRARY_PATH=/tmp`. Output (incl. the two
lazycasing warnings) unchanged.

NOTE for Track T: `pinned_tmp_paths()` in tools/testmgr.py existed solely for
this line and can now be deleted — that's T's file, so it is left to T.

## Log
- 2026-07-14 — resolved, commit HEAD.

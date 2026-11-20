---
slug: perf-c-a-header-heavy-unit-spends-most-of-its-compile-asking-ld-so-cache
track: C
prio: 55
type: perf
status: done
owner: "claude-pxx"
created: 2026-11-20
found-by: Rainyday 0050 (rump build through pxx, ~26 min at 3 jobs)
tags: [cfront, compile-time, rainyday]
blocked-by: []
summary: "DONE 2026-11-20. Rainyday rump replay 1627 s -> 386 s, 471 of 471 objects byte-identical. Rainyday's rump build replays 471 NetBSD compiles through pxx, about 10 s a file. Profiled (tools/pxxprof with a frame-pointer walk): most of a header-heavy unit's compile was spent outside the compiler proper. CHeaderLibraryFor asked /etc/ld.so.cache which library each prototype's header names, with a one-entry memo that NetBSD's interleaved headers missed nearly every time. Each ask decoded every cache entry into fresh strings, one character at a time. And CAddLibBuiltinDecls/CAddBitBuiltins ran 54 Pos() scans over the whole preprocessed unit. All three are fixed, every object byte-identical: amhphy.c 12.2 -> 1.8 s, if_wm.c 18.9 -> 4.9 s, kern_descrip.c 15.7 -> 2.2 s."
---

# A header-heavy C unit spends most of its compile asking ld.so.cache

## Measured

Rainyday's `tools/rump-pxx-build.sh` replays the gcc rump build's compiles
through pxx (`--emit-obj --freestanding --system-libs`). On plexus at load
around 20, a sample of every 20th job averaged 8.6 s a file, and a unit with an
empty body still costs only 0.5 s. So the time scales with the headers, not with
the code: amhphy.c is 7,300 lines after preprocessing and 3,017 procedures,
and its compile took 12 s.

Feeding gcc's preprocessed amhphy.c straight to pxx split it roughly in half
(6.6 s after the preprocessor). The profiler (`tools/pxxprof.c`, extended in
scratch to walk the rbp chain so runtime samples are charged to their
caller) put 45 percent of the whole compile under `CHeaderLibraryFor`.

## Causes and changes

1. **`CHeaderLibraryFor` (cparser.inc)** remembered only the LAST header path.
   A C unit's prototypes are not grouped by header, so nearly every
   declaration missed and paid three full scans of the cache. It is now a hashed
   table, one entry per header path.
2. **The three ld.so.cache lookups (pasparser_proc.inc)** each decoded every
   entry's key out of the file image on every call: `LdCacheStringAt` appended
   one character at a time, and the scans took a Copy and a LowerCase of each
   key's prefix. They are now served by:
   - **a memo per question** (`LdCacheFindSoname` / `LdCacheNativePathFor` /
     `LdCacheDirCandidate` wrap the original scans, renamed `*Scan`);
   - **one decode of the cache** (`LdIdxBuild`), with an exact-key chain and two
     prefix chains (through the first `.so.`, as spelled and lowered), all in
     cache order. Exact-before-case-insensitive and first-in-cache-order keep
     their meaning, and so do the truncation rules (key scan stops at the first
     unreadable key, path scan also at the first unreadable offset).
   - `LdCacheStringAt` finds the NUL, then takes one Copy.
   - `LdCacheDirCandidate`'s own scan is unchanged (memoised only).
3. **`CAddLibBuiltinDecls` / `CAddBitBuiltins` (cpreproc.inc)** asked Pos()
   once per builtin name they know, 34 and 20 times over the whole unit.
   `CBuiltinMentions` now collects each `__builtin_<ident>` and the character
   after it in one pass, which answers every one of those questions the same
   way. The match is not left-anchored, exactly like Pos.

## Result

| file | before | after |
|---|---|---|
| amhphy.c | 12.2 s | 1.8 s |
| if_wm.c | 18.9 s | 4.9 s |
| kern_descrip.c | 15.7 s | 2.2 s |
| pci_subr.c | 11.0 s | 3.1 s |
| if_rge.c | 14.0 s | 3.2 s |
| uimax.c | 1.9 s | 0.55 s |

All on a loaded host, so the absolute numbers are soft; the ratio is the claim.

**The whole replay**, all 471 compiles at 3 jobs, A/B against origin/master
(1785184108): **1627 s -> 386 s**, 0 failures on either side, and **all 471
objects byte-identical**.

## What is left (not this ticket)

After the change, a profile of if_wm.c shows ParseCSubroutine, IREmitNode,
the preprocessor (CPReadLine, AppendChar) and RecHasMisalignedFieldDepth
(6.9 percent inclusive, through IRFieldRaggedBit), with nothing dominant.

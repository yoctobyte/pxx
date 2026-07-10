---
prio: 56
---

# C: struct field resolves to offset 0 in the full sqlite unixFile (context-dependent)

- **Type:** bug (C frontend — struct field offset/resolution) — **Track A/C**.
- **Status:** ROOT CAUSE FOUND + FIXED 2026-07-10 — it was NOT a field-offset bug.
  The real cause is the preprocessor: `#if` didn't parse HEX literals, so
  `#if SQLITE_MAX_MMAP_SIZE>0` (`0x7fff0000`) evaluated FALSE at the `unixFile`
  struct (dropping the mmap fields → `mmapSize` lookup missed → default offset 0)
  while other `#if 0x..` sites also mis-evaluated. Fixed by making CPExprAtom /
  CPParsePoolNumber parse hex+octal (commit pending, regression b237). This
  offset-0 ticket is superseded by that fix; keeping it as the diagnostic trail.
- **Blocks:** was the apparent file-backed sqlite read wall; now the wall is the
  (correctly-enabled) mmap path itself — see the sqlite ticket.

## Symptom
In sqlite's `unixRead`, `pFile->mmapSize` and `pFile->pMapRegion` read GARBAGE
(e.g. mmapSize=8280375, pMapRegion=0x7e5937) even though `unixOpen` did
`memset(p, 0, sizeof(unixFile))`. The mmap fast-path
`if( offset < pFile->mmapSize )` then fires on a bogus mapping and
`memcpy(pBuf, &pMapRegion[offset], amt)` segfaults on the first page read of a
freshly-created db file. (`:memory:` never takes this path, so it is unaffected —
the extended in-memory suite still passes.)

## Root cause (localized, not yet fixed)
Instrumented at `unixOpen`'s memset:
```
sizeof(unixFile)=88  off(mmapSize)=0  off(pMapRegion)=0  off(h)=24
```
`h` (offset 24) is correct, but `mmapSize`/`pMapRegion` resolve to **offset 0** —
so `p->mmapSize` actually reads `pMethod` (the first member, a pointer) as a size,
and the memset only cleared 88 bytes (the true struct is larger). The fields ARE
parsed (no compile error on `&p->mmapSize`), but the field lookup yields offset 0
(FindUField miss → default 0) instead of the real offset (80 / 104).

pxx predefines `__linux__`, so `SQLITE_MAX_MMAP_SIZE` = `0x7fff0000` (>0): the mmap
fields AND the mmap code are BOTH compiled in — this is not a preprocessor on/off
mismatch. The field simply lands at offset 0.

`sizeof(unixFile)=88` is also too small: the real struct (through the mmap block)
needs the mmap i64s + pointer, so ~88 undercounts — consistent with the fields
after some point collapsing to offset 0 and not extending the layout.

## Landmine — context-dependent (isolated repro PASSES)
A standalone struct with the same head + `#if MMAP>0 { int; long long x3; void*; }`
mmap block computes EVERY offset byte-identical to gcc (sizeof=120, mmapSize=80,
pMapRegion=104). The bug only appears inside the FULL `unixFile` (compiler/…
duktape-class landmine: "isolated reproductions pass — the trigger needs the full
context"). The full struct has several more `#if` blocks
(`SQLITE_ENABLE_LOCKING_STYLE`, `__APPLE__`, `SQLITE_DEBUG`, `OS_VXWORKS`) and ~40
members. Reproduce by growing the minimal struct toward the full `unixFile`
(struct unixFile @ sqlite3.c ~38616) — add members / nested `#if` blocks until
`mmapSize` collapses to offset 0, then bisect to the exact trigger (likely a
member shape, a nested `#if`, or a field-table size cap like MAX_UFIELD /
UClsFBase window handling — cf. [[project_uclass_empty_window_rebase_fix]]).

## Gate
`make test` + self-host byte-identical + `make test-c-conformance` 220/220.
Regression: the reduced struct once it reproduces (`test/cstruct_field_offset_*_bNNN.c`).
Re-verify file-backed sqlite reads a page past `unixRead` afterwards.

[[task-sqlite-libc-free-runtime-bringup]]

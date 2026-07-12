---
prio: 50
---

# TObject.GetInterface(IID, out obj) — needs an interface GUID table

- **Type:** feature (Track A — RTTI / interfaces)
- **Track:** A — core (rtti_emit.inc, interface tables)
- **Status:** done — landed 2026-07-13.
- **Blocks:** [[feature-pascal-corpus-fpcunit]] (testutils.pp:43 —
  `TNoRefCountObject.QueryInterface` calls `GetInterface(IID, Obj)`).

## Why it is not a five-minute stub
FPC's `TObject.GetInterface(const IID: TGUID; out Obj): Boolean` looks an implemented
interface up **by GUID** at runtime and hands back the interface pointer.

**pxx interfaces default to CORBA and carry no GUIDs at all.** There is no table to
search, so nothing can be looked up.

The tempting shortcut — make GetInterface always return False — would let testutils
COMPILE and move the fpcunit chain to its next wall. **Do not.** A class that really
does implement the interface would then be told it does not, silently, with no
diagnostic. That is exactly the "compat finding that means silent wrong behavior"
the track rules say to promote to a real bug rather than paper over. If a stub is
ever wanted as a deliberate stepping stone it must be behind a flag and must say so.

## What it actually needs
1. **Record the GUID** an interface declares (`['{...}']`) — the parser currently
   accepts the literal and discards it.
2. **Emit an interface table per class**: for each implemented interface, {GUID, IMT
   pointer}. The IMT itself already exists (built per implemented interface at class
   parse time) — only the GUID key and a table to search are missing.
3. `GetInterface` walks that table (own + inherited), compares the 16-byte GUID, and
   on a hit stores the fat pointer {IMT, instance} into the out param.
4. It should reach the table the same way published-method reflection does — via the
   instance->RTTI backlink at VMT-8 that [[feature-rtti-method-reflection]] added.

Consider whether this should also imply `{$interfaces com}` semantics; it need not —
a GUID table is orthogonal to refcounting, and CORBA interfaces may carry GUIDs.

## Gate
`make test` + self-host byte-identical + cross. Interface layout changes, so
byte-identical self-host is the check that matters.

## Log
- 2026-07-13 — opened. Split out of [[feature-pascal-corpus-fpcunit]] once
  MethodAddress/MethodName landed and GetInterface became the only remaining
  compile blocker in testutils.

## Landed 2026-07-13

Built exactly as scoped, and the tempting stub was NOT taken.

1. The interface GUID literal is **recorded** instead of discarded — 16 raw bytes in
   TGuid memory order (D1 little-endian u32, D2/D3 little-endian u16, D4 in written
   order), so a compile-time blob compares byte-for-byte against a runtime `TGuid`
   with no marshalling. A malformed literal is still skipped rather than an error.
2. Each class RTTI blob gained an **interface table** (+80 count, +88 pointer;
   RTTI_CLS_SIZE 80 -> 96). One 24-byte entry per implemented interface that declared
   a GUID: the GUID inline, then a pointer to that (class, interface) IMT. The IMTs
   already existed — nothing had ever keyed them by GUID.
3. A class implementing a guided interface now gets a blob **even with no published
   members**, or a plain `class(TObject, IFoo)` would have been invisible to the lookup.
4. `__pxxGetInterface` walks the table (own + inherited via the parent chain) and, on a
   hit, writes the 16-byte fat pointer {IMT, instance} — which is what a pxx interface
   variable IS, so the result is immediately callable.
5. Reached through the same instance->RTTI backlink as
   [[feature-rtti-method-reflection]], and pulled by the same token pre-scan, so it
   works with no `uses` (FPC has it on TObject in System).

Both call shapes are rewritten. The BARE one is the one that mattered: it is how
testutils forwards an untyped `out` parameter. An `AN_ADDR` over a by-ref parameter
auto-derefs to the CALLER's address in IRLowerAddress, so one rewrite serves a plain
variable and a forwarded untyped `out` alike — that was the part worth checking rather
than assuming.

`IInterface` in the RTL now carries the canonical IUnknown GUID
`{00000000-0000-0000-C000-000000000046}`, without which there would still have been
nothing to find.

### Gate
make test green, self-host byte-identical (the RTTI blob GREW — that is the check that
matters), `testmgr --tier full` 1204/1204. Regression b257: qualified form, bare
implicit-Self form forwarding an untyped `out`, a correct MISS, and calling THROUGH the
returned interface (which is what proves the fat pointer is right).

### fpcunit
This clears the GetInterface blocker. testutils now advances to a new, unrelated wall:
`packed array` inside a record. Recorded on [[feature-pascal-corpus-fpcunit]].
